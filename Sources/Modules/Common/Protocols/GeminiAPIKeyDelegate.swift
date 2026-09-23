//
//  GeminiAPIKeyDelegate.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

// swiftlint:disable class_delegate_protocol

/// An interface for providing a Gemini API key.
///
/// Conform to `GeminiAPIKeyDelegate` and register your implementation
/// with ``LanguageModel/registerGeminiAPIKeyDelegate(_:)`` to enable
/// requests to Gemini:
///
/// ```swift
/// struct APIKeyProvider: GeminiAPIKeyDelegate {
///     let apiKey = "…"
/// }
///
/// LanguageModel.registerGeminiAPIKeyDelegate(APIKeyProvider())
/// ```
public protocol GeminiAPIKeyDelegate: Sendable {
    /// The API key used to authenticate requests to Gemini.
    var apiKey: String { get }
}

// swiftlint:enable class_delegate_protocol
