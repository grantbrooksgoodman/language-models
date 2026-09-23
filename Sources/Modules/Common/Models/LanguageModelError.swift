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

    /// A human-verification challenge must be resolved before the
    /// request can proceed.
    case challengeRequired

    /// The model returned an empty reply.
    case emptyResponse

    /// The prompt was empty after trimming whitespace.
    case invalidPrompt

    /// Evaluating JavaScript in the web view failed.
    ///
    /// The associated value, when present, describes the underlying
    /// JavaScript error.
    case javaScriptEvaluationFailed(String? = nil)

    /// No API key was available for the request.
    case missingAPIKey

    /// The page's state could not be read.
    ///
    /// This typically indicates that the page's structure changed and
    /// the state probe returned an unexpected result.
    case pageStateUnavailable

    /// The network request failed.
    ///
    /// The associated value describes the failure.
    case requestFailed(String)

    /// The session did not become ready in time.
    ///
    /// The composer never appeared, or a challenge remained
    /// unresolved, within the readiness window.
    case sessionNotReady

    /// The prompt could not be submitted.
    ///
    /// The associated value describes why submission failed.
    case submissionFailed(String)

    // MARK: - Properties

    /// A localized, human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .challengeRequired:
            "A verification challenge must be resolved."

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
