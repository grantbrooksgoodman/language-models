//
//  GeminiResponse.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct GeminiResponse: Decodable {
    // MARK: - Types

    struct Candidate: Decodable {
        let content: Content?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
    }

    // MARK: - Properties

    let candidates: [Candidate]?

    // MARK: - Computed Properties

    /// The concatenated text of the first candidate's reply, if any.
    var text: String? {
        guard let parts = candidates?.compactMap(\.content).first?.parts else { return nil }
        return parts.compactMap(\.text).joined()
    }
}
