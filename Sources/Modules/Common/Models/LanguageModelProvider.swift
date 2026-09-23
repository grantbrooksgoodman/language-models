//
//  LanguageModelProvider.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// A language model backend that a ``LanguageModelSession`` can use.
///
/// Pass a provider when creating a session to target a specific
/// backend:
///
/// ```swift
/// let session = LanguageModelSession(.gemini(config: .init()))
/// ```
///
/// A session created without an explicit provider uses Gemini for its
/// API-level response times, falling back to ChatGPT if the Gemini
/// request fails.
public enum LanguageModelProvider: Sendable {
    /// ChatGPT, driven through its web app in a hidden web view.
    case chatGPT

    /// Gemini, called directly through its API with the given
    /// configuration.
    case gemini(config: GeminiConfig)
}
