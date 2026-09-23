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
    let isLoggedOutModalPresent: Bool
    let isStreaming: Bool
    let urlConversationID: String?
}
