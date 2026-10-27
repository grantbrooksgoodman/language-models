//
//  ChatGPTStreamCompletion.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTStreamCompletion: Decodable, Equatable {
    /// The labels a source citation in the message may be rendered
    /// with, in any text source.
    let citationLabels: [String]
    let fullText: String
    let isFullTextIncomplete: Bool
    let messageID: String?
}
