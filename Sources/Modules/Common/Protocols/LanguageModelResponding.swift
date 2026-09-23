//
//  LanguageModelResponding.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// A single language model backend that answers prompts. Each provider
/// (ChatGPT, Gemini) has its own conforming type, which
/// ``LanguageModelSession`` dispatches to.
@MainActor
protocol LanguageModelResponding {
    /// Loads any resources the backend needs ahead of the first prompt.
    func prewarm()

    /// Returns the backend's reply to the given prompt.
    func response(to prompt: String) async throws(LanguageModelError) -> String

    /// Abandons the current conversation and starts a fresh one.
    func startNewConversation() async throws(LanguageModelError)
}
