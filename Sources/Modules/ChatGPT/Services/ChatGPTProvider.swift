//
//  ChatGPTProvider.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

@MainActor
final class ChatGPTProvider: LanguageModelResponding {
    // MARK: - Properties

    private let host = ChatGPTWebViewHost()

    // MARK: - Methods

    func prewarm() {
        host.load()
    }

    func response(to prompt: String) async throws(LanguageModelError) -> String {
        try await host.respondViaComposer(prompt)
    }

    func startNewConversation() async throws(LanguageModelError) {
        try await host.startNewChat()
    }
}
