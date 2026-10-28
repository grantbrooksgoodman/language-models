//
//  ChatGPTScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Scripts injected at document start, for the main frame only, that
/// suppress permission prompts, keep the page reporting itself as
/// visible, and speed up its initial load.
enum ChatGPTScripts {
    /// Every script injected at document start, for the main frame
    /// only, other than the bridge.
    static let documentStartScripts = [
        denyPermissions,
        fauxVisibility,
        promoteIdleCallback,
    ]

    static let denyPermissions = ChatGPTScript(name: "denyPermissions")
    static let fauxVisibility = ChatGPTScript(name: "fauxVisibility")
    static let promoteIdleCallback = ChatGPTScript(name: "promoteIdleCallback")
}
