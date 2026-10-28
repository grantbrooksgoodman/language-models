//
//  ChatGPTStreamReaderScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The fragments of the fetch interceptor that parse the mobile-web
/// conversation reply, one per stream format.
enum ChatGPTStreamReaderScripts {
    static let conversationSourceReader = ChatGPTScript(name: "conversationSourceReader")
    static let partialHTMLReader = ChatGPTScript(name: "partialHTMLReader")
}
