//
//  GeminiRequest.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct GeminiRequest: Encodable {
    // MARK: - Types

    struct Content: Encodable {
        let parts: [Part]
        let role: String
    }

    struct Part: Encodable {
        let text: String
    }

    // MARK: - Properties

    let contents: [Content]
    let systemInstruction: Content?
}
