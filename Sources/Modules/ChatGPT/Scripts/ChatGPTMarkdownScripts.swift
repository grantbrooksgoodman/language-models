//
//  ChatGPTMarkdownScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The fragment of the fetch interceptor that unescapes a message's
/// `fallbackMarkdown` rendering.
enum ChatGPTMarkdownScripts {
    static let unescaper = ChatGPTScript(name: "unescaper")
}
