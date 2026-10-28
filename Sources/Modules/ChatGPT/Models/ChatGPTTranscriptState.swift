//
//  ChatGPTTranscriptState.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTTranscriptState: Decodable, Equatable {
    // MARK: - Properties

    let composerText: String
    let isAnchorPresent: Bool
    let lastAssistantMessageID: String?
    let lastUserMessageID: String?

    // MARK: - Methods

    func hasNewUserMessage(
        since baseline: ChatGPTTranscriptState?
    ) -> Bool {
        guard let baseline,
              let lastUserMessageID else { return false }

        return lastUserMessageID != baseline.lastUserMessageID
    }
}
