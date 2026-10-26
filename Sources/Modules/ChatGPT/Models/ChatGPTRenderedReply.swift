//
//  ChatGPTRenderedReply.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTRenderedReply: Decodable, Equatable {
    let isComplete: Bool
    let messageID: String?
    let text: String
}
