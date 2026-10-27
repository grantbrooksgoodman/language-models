//
//  ChatGPTRenderedReply.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTRenderedReply: Decodable, Equatable {
    // MARK: - Types

    /// Describes a link in the reply – its markup and layout, not its
    /// text – and whether it was skipped as a citation chip.
    struct LinkDescriptor: Decodable, Equatable {
        let attributes: [String]
        let display: String
        let isChip: Bool
        let tag: String
        let textLength: Int
    }

    // MARK: - Properties

    let isComplete: Bool
    let linkDescriptors: [LinkDescriptor]
    let messageID: String?
    let text: String
}
