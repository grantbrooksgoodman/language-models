//
//  ChatGPTScript.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// An injected script, identified by its name in `manifest.json`.
struct ChatGPTScript: Hashable {
    let name: String
}
