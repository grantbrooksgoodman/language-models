//
//  LanguageModels.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The top-level entry point for the language model system.
///
/// Use `LanguageModels` to register the delegates a
/// ``LanguageModelSession`` needs, and to answer several prompts
/// concurrently with ``responses(to:using:)``.
///
/// Register a Gemini API key delegate once, early in the app's
/// lifecycle, to enable the Gemini provider:
///
/// ```swift
/// LanguageModels.registerGeminiAPIKeyDelegate(APIKeyProvider())
/// ```
public enum LanguageModels {
    // MARK: - Properties

    /// The registered Gemini API key delegate, or `nil` if none has
    /// been registered.
    @MainActor
    private(set) static var geminiAPIKeyDelegate: GeminiAPIKeyDelegate?

    // MARK: - Methods

    /// Registers the delegate that supplies the Gemini API key.
    ///
    /// Calling this method replaces any previously registered delegate.
    ///
    /// - Parameter delegate: The delegate that supplies the API key.
    @MainActor
    public static func registerGeminiAPIKeyDelegate(
        _ delegate: GeminiAPIKeyDelegate
    ) {
        geminiAPIKeyDelegate = delegate
    }

    /// Sends each prompt to a language model concurrently and returns a
    /// dictionary mapping every prompt to its reply.
    ///
    /// Each prompt is answered independently by its own
    /// ``LanguageModelSession``, up to ten at a time. Duplicate prompts –
    /// within this batch or across concurrent calls – share a single
    /// in-flight request, and collapse to one entry in the returned
    /// dictionary. If any prompt fails, the whole batch fails.
    ///
    /// ```swift
    /// let replies = try await LanguageModels.responses(
    ///     to: ["What is 2 + 2?", "Capital of France?"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - prompts: The prompts to answer.
    ///   - provider: The provider used for every prompt. The default is
    ///     ``LanguageModelProvider/gemini(config:)`` with a default
    ///     configuration.
    ///
    /// - Returns: A dictionary mapping each prompt to its reply.
    ///
    /// - Throws: ``LanguageModelError`` if any prompt fails.
    public static func responses(
        to prompts: [String],
        using provider: LanguageModelProvider = .gemini(config: .init())
    ) async throws -> [String: String] {
        let prompts = Array(Set(prompts))

        let providerKey = switch provider {
        case .chatGPT:
            "chatGPT"

        case let .gemini(config):
            "gemini|\(config.model.rawValue)|\(config.systemMessage ?? "")"
        }

        var replies = [String: String]()

        try await withThrowingTaskGroup(
            of: (String, String).self
        ) { taskGroup in
            var nextIndex = 0

            func enqueueNextTask() {
                guard nextIndex < prompts.count else { return }
                let index = nextIndex
                nextIndex += 1

                let prompt = prompts[index]
                taskGroup.addTask {
                    let reply = try await InFlightResponseCoordinator.shared.task(
                        forKey: "\(providerKey)|\(prompt)"
                    ) {
                        let session = await LanguageModelSession(provider)
                        return try await session.response(to: prompt)
                    }.value

                    return (prompt, reply)
                }
            }

            let maxConcurrentOperations = min(
                10,
                prompts.count
            )

            for _ in 0 ..< maxConcurrentOperations {
                enqueueNextTask()
            }

            // As each task finishes, enqueue another until done.
            for try await (prompt, reply) in taskGroup {
                replies[prompt] = reply
                enqueueNextTask()
            }
        }

        return replies
    }
}
