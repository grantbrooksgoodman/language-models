//
//  LanguageModelSession.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

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
/// - Important: `LanguageModelSession` is main-actor isolated. Call its
///   methods from the main actor. Using Gemini requires a key registered
///   with ``LanguageModels/registerGeminiAPIKeyDelegate(_:)``. Once a
///   session prewarms or sends a prompt to ChatGPT, it holds a hidden
///   web view until it is released.
@MainActor
public final class LanguageModelSession {
    // MARK: - Properties

    private let responders: [any LanguageModelResponding]

    private var conversationResponder: (any LanguageModelResponding)?
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
    ///   ``LanguageModelError/conversationLost`` when the page no
    ///   longer shows the conversation – for example, after its web
    ///   content process is terminated – and loading the conversation
    ///   again does not restore it. The next turn starts a fresh
    ///   conversation.
    public func response(
        to prompt: String
    ) async throws(LanguageModelError) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidPrompt
        }

        try await waitForTurn()
        defer { finishTurn() }

        guard let conversationResponder else {
            return try await firstResponse(to: trimmed)
        }

        do throws(LanguageModelError) {
            return try await conversationResponder.response(to: trimmed)
        } catch .conversationLost {
            self.conversationResponder = nil
            throw .conversationLost
        }
    }

    /// Abandons the current conversation and starts a fresh one, so the
    /// next call to ``response(to:)`` is not continued from prior turns.
    ///
    /// For a session created with ``init()``, the next turn tries
    /// Gemini, then ChatGPT, again. The call runs once the session's
    /// earlier calls have finished, and returns at once if the session
    /// has not loaded ChatGPT.
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

        for responder in responders {
            try await responder.startNewConversation()
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
                let reply = try await responder.response(to: prompt)
                conversationResponder = responder
                return reply
            } catch .cancelled {
                throw .cancelled
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func waitForTurn() async throws(LanguageModelError) {
        guard !Task.isCancelled else {
            throw .cancelled
        }

        guard isRunningCall else {
            isRunningCall = true
            return
        }

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
