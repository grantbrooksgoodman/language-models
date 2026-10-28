//
//  ChatGPTScriptManifest.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct ChatGPTScriptManifest: Decodable {
    // MARK: - Types

    struct Script: Decodable {
        let arguments: [String]?
        let kind: String
    }

    // MARK: - Properties

    let compositions: [String: [String]]
    let placeholders: [String]
    let scripts: [String: Script]
}
