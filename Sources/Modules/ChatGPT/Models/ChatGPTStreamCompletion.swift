//
//  ChatGPTStreamCompletion.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTStreamCompletion: Decodable, Equatable {
    let fullText: String
    let isFullTextIncomplete: Bool
    let messageID: String?
}
