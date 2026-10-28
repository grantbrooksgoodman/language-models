//
//  LanguageModelSession.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation
import UIKit

/// A conversation with a language model.
///
/// Send a prompt with ``response(to:)`` and await the model's reply.
/// Each call continues the conversation from the previous turns, so
/// the model retains context. Create a session with no provider to
/// use the default behavior – Gemini for its API-level response
/// times, falling back to ChatGPT if the Gemini request fails:
///
/// ```swift
/// let session = LanguageModelSession()
/// let reply = try await session.response(to: "Echo BANANA and nothing else.")
/// ```
///
/// Pass a provider to target one backend, with no fallback:
///
/// ```swift
/// let session = LanguageModelSession(.chatGPT)
/// ```
///
/// A session's calls run one at a time, in the order they were made.
/// Sessions are independent and may run concurrently.
///
/// - Important: `LanguageModelSession` is main-actor isolated. Create
///   it and call its methods from the main actor. Using Gemini requires
///   a key registered with
///   ``LanguageModels/registerGeminiAPIKeyDelegate(_:)``. A session
///   that has used ChatGPT holds the resources ChatGPT needs until the
///   session is released.
@MainActor
public final class LanguageModelSession {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    private let responders: [any LanguageModelResponding]

    private var conversationResponder: (any LanguageModelResponding)?

    private var hasBackgroundTimeExpired = false

    private var isRunningCall = false

    private var waitingCalls = [(id: UUID, continuation: CheckedContinuation<Bool, Never>)]()

    // MARK: - Init

    /// Creates a session that uses Gemini, falling back to ChatGPT if
    /// the Gemini request fails.
    ///
    /// The first turn of a conversation tries Gemini, then ChatGPT. The
    /// provider that replies to the first turn answers every later
    /// turn of the conversation, with no fallback. If that provider
    /// fails, the call throws, and the next turn goes to the same
    /// provider. If it throws ``LanguageModelError/conversationLost``,
    /// the next turn starts over with Gemini.
    public init() {
        responders = [
            GeminiProvider(config: .init()),
            ChatGPTProvider(),
        ]
    }

    /// Creates a session that uses a single provider, with no fallback.
    ///
    /// - Parameter provider: The provider to use.
    public init(_ provider: LanguageModelProvider) {
        responders = [Self.responder(for: provider)]
    }

    // MARK: - Methods

    /// Loads any resources the session's providers need ahead of the
    /// first prompt.
    ///
    /// Call this method once a prompt is imminent to reduce the latency
    /// of the first reply. It is safe to call repeatedly and never
    /// throws. Unlike the session's other methods, it runs at once
    /// rather than waiting for the calls before it.
    public func prewarm() {
        for responder in responders {
            responder.prewarm()
        }
    }

    /// Sends the given prompt to the model and returns its reply.
    ///
    /// ```swift
    /// let reply = try await session.response(to: "Explain optionals in Swift.")
    /// ```
    ///
    /// The call runs once the session's earlier calls have finished. A
    /// call that is cancelled while waiting its turn throws
    /// ``LanguageModelError/cancelled`` before it runs.
    ///
    /// - Important: The session requests background execution time
    ///   while a reply is in progress, and throws
    ///   ``LanguageModelError/interrupted`` if that time expires.
    ///
    /// - Parameter prompt: The prompt to send. Must not be empty after
    ///   trimming whitespace.
    ///
    /// - Returns: The model's reply.
    ///
    /// - Throws: ``LanguageModelError`` if the prompt is invalid or the
    ///   provider can't produce a reply. On the first turn of a session
    ///   created with ``init()``, the error is thrown only if every
    ///   provider fails. If the task that called the method is
    ///   cancelled, the call throws ``LanguageModelError/cancelled``
    ///   without trying another provider. ChatGPT throws
    ///   ``LanguageModelError/conversationLost`` when its conversation
    ///   is lost and cannot be restored. The next turn starts a fresh
    ///   conversation.
    public func response(
        to prompt: String
    ) async throws(LanguageModelError) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log(
                "The prompt is empty.",
                level: .error,
                error: .invalidPrompt
            )

            throw .invalidPrompt
        }

        try await waitForTurn()
        defer { finishTurn() }

        return try await perform { [self] () async throws(LanguageModelError) -> String in
            guard let conversationResponder else {
                return try await firstResponse(to: trimmed)
            }

            log("Sending the prompt to \(name(of: conversationResponder)).")
            do throws(LanguageModelError) {
                return try await conversationResponder.response(to: trimmed)
            } catch .conversationLost {
                log("The conversation was lost; the next turn starts over.")
                self.conversationResponder = nil
                throw .conversationLost
            }
        }
    }

    /// Abandons the current conversation and starts a fresh one, so the
    /// next call to ``response(to:)`` is not continued from prior turns.
    ///
    /// For a session created with ``init()``, the next turn tries
    /// Gemini, then ChatGPT, again. The call runs once the session's
    /// earlier calls have finished, and returns at once if the session
    /// has not used ChatGPT.
    ///
    /// - Throws: ``LanguageModelError`` if a fresh conversation cannot
    ///   be started. If the task that called the method is cancelled,
    ///   the call throws ``LanguageModelError/cancelled``.
    public func startNewConversation() async throws(LanguageModelError) {
        try await waitForTurn()
        defer {
            conversationResponder = nil
            finishTurn()
        }

        try await perform { [self] () async throws(LanguageModelError) in
            log("Starting a new conversation.")
            for responder in responders {
                try await responder.startNewConversation()
            }
        }
    }

    // MARK: - Auxiliary

    private static func responder(
        for provider: LanguageModelProvider
    ) -> any LanguageModelResponding {
        switch provider {
        case .chatGPT: ChatGPTProvider()
        case let .gemini(config): GeminiProvider(config: config)
        }
    }

    private func cancelWaitingCall(id: UUID) {
        guard let index = waitingCalls.firstIndex(where: { $0.id == id }) else { return }
        waitingCalls.remove(at: index).continuation.resume(returning: false)
    }

    private func finishTurn() {
        guard waitingCalls.isEmpty else {
            return waitingCalls.removeFirst().continuation.resume(returning: true)
        }

        isRunningCall = false
    }

    private func firstResponse(
        to prompt: String
    ) async throws(LanguageModelError) -> String {
        var lastError: LanguageModelError = .emptyResponse
        for responder in responders {
            do throws(LanguageModelError) {
                log("Sending the first prompt to \(name(of: responder)).")
                let reply = try await responder.response(to: prompt)
                conversationResponder = responder
                log("Pinned the conversation to \(name(of: responder)).")
                return reply
            } catch .cancelled {
                throw .cancelled
            } catch {
                log(
                    "\(name(of: responder)) failed: \(error.localizedDescription)",
                    level: .error,
                    error: error
                )

                lastError = error
            }
        }

        throw lastError
    }

    private func languageModelError(from error: any Error) -> LanguageModelError {
        switch error {
        case LanguageModelError.cancelled where hasBackgroundTimeExpired: .interrupted
        case let error as LanguageModelError: error
        case is CancellationError: .cancelled
        default: .requestFailed(error.localizedDescription)
        }
    }

    /// The unit of work throws only `LanguageModelError`, which the
    /// task erases; a cancellation that followed the expiration of the
    /// background task's time is reported as an interruption.
    private func log(
        _ message: String,
        level: LanguageModelLogEntry.Level = .info,
        error: LanguageModelError? = nil,
        fileName: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        LoggingService.log(
            message,
            level: level,
            category: Strings.sessionLoggerCategory,
            error: error,
            fileName: fileName,
            function: function,
            line: line
        )
    }

    /// The unit of work runs in a background task, whose expiration
    /// cancels it; the session then reports the interruption rather
    /// than a cancellation.
    private func name(of responder: any LanguageModelResponding) -> String {
        responder is GeminiProvider ? "Gemini" : "ChatGPT"
    }

    private func perform<Value: Sendable>(
        _ work: @escaping @MainActor @Sendable () async throws(LanguageModelError) -> Value
    ) async throws(LanguageModelError) -> Value {
        hasBackgroundTimeExpired = false
        let unit = Task { @MainActor in
            try await work()
        }

        let identifier = UIApplication.shared.beginBackgroundTask(withName: Strings.backgroundTaskName) { [weak self] in
            self?.log(
                "Background execution time expired; interrupting the call.",
                level: .error
            )

            self?.hasBackgroundTimeExpired = true
            unit.cancel()
        }

        defer {
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }

        let result = await withTaskCancellationHandler {
            await unit.result
        } onCancel: {
            unit.cancel()
        }

        switch result {
        case let .success(value):
            return value

        case let .failure(error):
            let error = languageModelError(from: error)
            if case .cancelled = error {
                log("The call was cancelled.")
            } else {
                log(
                    "The call failed: \(error.localizedDescription)",
                    level: .error,
                    error: error
                )
            }

            throw error
        }
    }

    private func waitForTurn() async throws(LanguageModelError) {
        guard !Task.isCancelled else {
            throw .cancelled
        }

        guard isRunningCall else {
            isRunningCall = true
            return
        }

        log(
            "Waiting for the session's current call to finish.",
            level: .debug
        )

        let id = UUID()
        let isTurnGranted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waitingCalls.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelWaitingCall(id: id)
            }
        }

        guard isTurnGranted else {
            throw .cancelled
        }
    }
}
