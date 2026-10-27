//
//  GeminiErrorResponse.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct GeminiErrorResponse: Decodable {
    // MARK: - Types

    struct Detail: Decodable {
        let message: String?
    }

    // MARK: - Properties

    let error: Detail?
}
