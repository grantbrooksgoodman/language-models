//
//  LanguageModelError.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// An error that occurs while sending a prompt to a language model or
/// reading its reply.
///
/// `LanguageModelError` conforms to `LocalizedError`, providing a
/// human-readable ``errorDescription`` for each case. You receive these
/// errors when a ``LanguageModelSession`` method throws:
///
/// ```swift
/// do {
///     let reply = try await session.response(to: "Hello")
/// } catch {
///     print(error.localizedDescription)
/// }
/// ```
///
/// Some cases include an associated `String` value with additional
/// detail about the failure.
public enum LanguageModelError: LocalizedError {
    // MARK: - Cases

    /// The task that called the method was cancelled.
    case cancelled

    /// A human-verification challenge must be resolved before the
    /// request can proceed.
    ///
    /// Set ``LanguageModels/presentsChallenges`` to `true` to show the
    /// challenge so you can solve it.
    case challengeRequired

    /// The provider can no longer continue the current conversation.
    ///
    /// ChatGPT throws this error when its conversation is lost and
    /// cannot be restored. The next turn starts a fresh conversation.
    case conversationLost

    /// The model returned an empty reply, or no reply arrived in time.
    case emptyResponse

    /// The prompt was empty after trimming whitespace.
    case invalidPrompt

    /// A step of the ChatGPT request could not run.
    ///
    /// The associated value, when present, describes the failure.
    case javaScriptEvaluationFailed(String? = nil)

    /// No API key was available for the request.
    case missingAPIKey

    /// ChatGPT's state could not be read.
    case pageStateUnavailable

    /// The network request failed.
    ///
    /// The associated value describes the failure. For ChatGPT, it
    /// could not be reached – for example, because the device is
    /// offline.
    case requestFailed(String)

    /// The session did not become ready in time.
    ///
    /// ChatGPT did not become ready to accept a prompt, or a challenge
    /// remained unresolved, in time.
    case sessionNotReady

    /// The prompt could not be submitted.
    ///
    /// The associated value describes why submission failed.
    case submissionFailed(String)

    // MARK: - Properties

    /// A localized, human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "The request was cancelled."

        case .challengeRequired:
            "A verification challenge must be resolved."

        case .conversationLost:
            "The conversation can no longer be continued."

        case .emptyResponse:
            "The response was empty."

        case .invalidPrompt:
            "The prompt is empty."

        case let .javaScriptEvaluationFailed(errorDescription):
            "Failed to evaluate JavaScript: \(errorDescription ?? "An unknown error occurred.")"

        case .missingAPIKey:
            "No API key has been provided."

        case .pageStateUnavailable:
            "The page state is unavailable."

        case let .requestFailed(reason):
            "The request failed: \(reason)"

        case .sessionNotReady:
            "The session is not ready."

        case let .submissionFailed(reason):
            "Failed to submit the prompt: \(reason)"
        }
    }
}
