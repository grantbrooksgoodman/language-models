//
//  ChatGPTPageState.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTPageState: Decodable, Equatable {
    let isChallengePresent: Bool
    let isComposerPresent: Bool
    let isLastAssistantMessageComplete: Bool
    let isLoggedOutModalPresent: Bool
    let isStreaming: Bool
    let lastAssistantMessageID: String?
    let lastUserMessageID: String?
    let urlConversationID: String?
}
