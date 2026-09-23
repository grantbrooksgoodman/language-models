//
//  GeminiConfig.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The configuration for a Gemini request.
///
/// Use `GeminiConfig` to choose the model and, optionally, a system
/// message that steers how the model responds. The system message is
/// sent alongside the user prompt passed to
/// ``LanguageModelSession/response(to:)``:
///
/// ```swift
/// let config = GeminiConfig(systemMessage: "Answer in one word.")
/// let session = LanguageModelSession(.gemini(config: config))
/// ```
public struct GeminiConfig: Sendable {
    // MARK: - Properties

    /// The model that answers the prompt.
    public let model: GeminiModel

    /// An optional instruction that steers the model's response,
    /// sent alongside the user prompt.
    public let systemMessage: String?

    // MARK: - Init

    /// Creates a Gemini configuration.
    ///
    /// - Parameters:
    ///   - model: The model that answers the prompt. The default is
    ///     ``GeminiModel/flash25``.
    ///   - systemMessage: An optional instruction that steers the
    ///     model's response. The default is `nil`.
    public init(
        model: GeminiModel = .flash25,
        systemMessage: String? = nil
    ) {
        self.model = model
        self.systemMessage = systemMessage
    }
}
