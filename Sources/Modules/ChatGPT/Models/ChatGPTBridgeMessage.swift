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
        case generation
        case state
        case type
    }

    // MARK: - Cases

    case completed(ChatGPTStreamCompletion)
    case pageState(ChatGPTPageState)
    case started(generation: Int?)

    // MARK: - Properties

    var generation: Int? {
        switch self {
        case let .completed(completion): completion.generation
        case .pageState: nil
        case let .started(generation): generation
        }
    }

    // MARK: - Init

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(String.self, forKey: .type) {
        case "completed":
            self = try .completed(.init(from: decoder))

        case "pageState":
            self = try .pageState(container.decode(
                ChatGPTPageState.self,
                forKey: .state
            ))

        case "started":
            self = try .started(generation: container.decodeIfPresent(
                Int.self,
                forKey: .generation
            ))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown bridge message type."
            )
        }
    }
}
