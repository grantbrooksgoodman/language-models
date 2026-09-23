//
//  ChatGPTBridgeMessage.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

enum ChatGPTBridgeMessage: Decodable {
    // MARK: - Types

    private enum CodingKeys: String, CodingKey {
        case fullText
        case type
    }

    // MARK: - Cases

    case completed(fullText: String)

    // MARK: - Init

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(String.self, forKey: .type) {
        case "completed":
            self = try .completed(
                fullText: container.decode(String.self, forKey: .fullText)
            )

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown bridge message type."
            )
        }
    }
}
