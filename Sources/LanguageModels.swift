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
    // MARK: - Constants Accessors

    private typealias Ints = Constants.Ints

    // MARK: - Properties

    /// The registered Gemini API key delegate, or `nil` if none has
    /// been registered.
    @MainActor
    private(set) static var geminiAPIKeyDelegate: GeminiAPIKeyDelegate?

    /// The registered log delegate, or `nil` if none has been
    /// registered.
    @MainActor
    private(set) static var logDelegate: LanguageModelLogDelegate?

    /// The amount of detail LanguageModels logs.
    ///
    /// Entries go to the delegate registered with
    /// ``registerLogDelegate(_:)``, or to the unified logging system
    /// under the `LanguageModels` subsystem. The default is
    /// ``LanguageModelLogLevel/off``.
    ///
    /// - Important: ``LanguageModelLogLevel/debug`` logs the text of
    ///   every prompt and reply.
    @MainActor
    public static var logLevel = LanguageModelLogLevel.off

    /// A Boolean value that indicates whether the ChatGPT provider
    /// shows a human-verification challenge so you can solve it.
    ///
    /// A challenge that does not clear on its own within fifteen
    /// seconds makes a ``LanguageModelSession`` method throw
    /// ``LanguageModelError/challengeRequired``. Set this property to
    /// `true` to instead present the challenge over your app's key
    /// window, with a close button, for up to two minutes:
    ///
    /// ```swift
    /// LanguageModels.presentsChallenges = true
    /// ```
    ///
    /// The default is `false`.
    ///
    /// - Important: The challenge covers your app's interface while
    ///   it is shown, and the call that triggered it waits
    ///   until the challenge clears, the close button is tapped, or
    ///   two minutes pass. Presenting requires a key window; without
    ///   one, the call throws ``LanguageModelError/challengeRequired``.
    ///   Tapping the close button also throws it.
    @MainActor
    public static var presentsChallenges = false

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

    /// Registers the delegate that receives the entries LanguageModels
    /// logs.
    ///
    /// Calling this method replaces any previously registered delegate.
    /// Entries are logged only for the levels ``logLevel`` includes.
    ///
    /// - Parameter delegate: The delegate that receives the entries.
    @MainActor
    public static func registerLogDelegate(
        _ delegate: LanguageModelLogDelegate
    ) {
        logDelegate = delegate
    }

    /// Sends each prompt to a language model concurrently and returns a
    /// dictionary mapping every prompt to its reply.
    ///
    /// Each prompt is answered independently by its own
    /// ``LanguageModelSession``, up to ten at a time, or two at a time
    /// with ``LanguageModelProvider/chatGPT``, because ChatGPT-backed
    /// sessions are resource-intensive. Duplicate prompts – within a
    /// batch or across concurrent calls – share a single in-flight
    /// request, and collapse to one entry in the returned dictionary.
    /// If any prompt fails, the whole batch fails, and its other
    /// prompts are cancelled.
    ///
    /// ```swift
    /// let replies = try await LanguageModels.responses(
    ///     to: ["What is 2 + 2?", "Capital of France?"]
    /// )
    /// ```
    ///
    /// If the task that called the method is cancelled, the call throws
    /// ``LanguageModelError/cancelled``, and each in-flight request that
    /// no other call is waiting on stops.
    ///
    /// - Important: Cancelling a call does not cancel a request that
    ///   another concurrent call is still waiting on. That request
    ///   continues for the other call.
    ///
    /// - Parameters:
    ///   - prompts: The prompts to answer.
    ///   - provider: The provider used for every prompt. The default is
    ///     ``LanguageModelProvider/gemini(config:)`` with a default
    ///     configuration.
    ///
    /// - Returns: A dictionary mapping each prompt to its reply.
    ///
    /// - Throws: ``LanguageModelError`` if any prompt fails. If the task
    ///   that called the method is cancelled, the call throws
    ///   ``LanguageModelError/cancelled``.
    public static func responses(
        to prompts: [String],
        using provider: LanguageModelProvider = .gemini(config: .init())
    ) async throws(LanguageModelError) -> [String: String] {
        let prompts = Array(Set(prompts))

        let providerKey = switch provider {
        case .chatGPT:
            "chatGPT"

        case let .gemini(config):
            "gemini|\(config.model.rawValue)|\(config.systemMessage ?? "")"
        }

        var replies = [String: String]()

        do {
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
                        let reply = try await InFlightResponseCoordinator.shared.response(
                            forKey: "\(providerKey)|\(prompt)"
                        ) { () async throws(LanguageModelError) in
                            let session = await LanguageModelSession(provider)
                            return try await session.response(to: prompt)
                        }

                        return (prompt, reply)
                    }
                }

                let maxConcurrentOperations = min(
                    maxConcurrentOperations(for: provider),
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
        } catch let error as LanguageModelError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            // Unreachable: every child task throws a `LanguageModelError`.
            throw .requestFailed(error.localizedDescription)
        }

        return replies
    }

    // MARK: - Auxiliary

    private static func maxConcurrentOperations(
        for provider: LanguageModelProvider
    ) -> Int {
        switch provider {
        case .chatGPT: Ints.maxConcurrentChatGPTOperations
        case .gemini: Ints.maxConcurrentGeminiOperations
        }
    }
}
