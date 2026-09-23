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
/// Create a session with no provider to use the default behavior –
/// Gemini for its API-level response times, falling back to ChatGPT if
/// the Gemini request fails:
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
/// Sessions are independent and may run concurrently.
///
/// - Important: `LanguageModelSession` is main-actor isolated. Call its
///   methods from the main actor. Using Gemini requires a key registered
///   with ``LanguageModel/registerGeminiAPIKeyDelegate(_:)``.
@MainActor
public final class LanguageModelSession {
    // MARK: - Properties

    private let responders: [any LanguageModelResponding]

    // MARK: - Init

    /// Creates a session that uses Gemini, falling back to ChatGPT if
    /// the Gemini request fails.
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
    /// throws.
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
    /// - Parameter prompt: The prompt to send. Must not be empty after
    ///   trimming whitespace.
    ///
    /// - Returns: The model's reply.
    ///
    /// - Throws: ``LanguageModelError`` if the prompt is invalid or no
    ///   provider can produce a reply.
    public func response(
        to prompt: String
    ) async throws(LanguageModelError) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidPrompt
        }

        var lastError: LanguageModelError = .emptyResponse
        for responder in responders {
            do throws(LanguageModelError) {
                return try await responder.response(to: trimmed)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    /// Abandons the current conversation and starts a fresh one, so the
    /// next call to ``response(to:)`` is not continued from prior turns.
    ///
    /// - Throws: ``LanguageModelError`` if a fresh conversation cannot
    ///   be started.
    public func startNewConversation() async throws(LanguageModelError) {
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
}
