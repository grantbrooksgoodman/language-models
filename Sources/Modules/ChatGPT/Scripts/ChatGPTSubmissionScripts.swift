//
//  ChatGPTSubmissionScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// On-demand scripts that drive the page: inserting a prompt into the
/// composer, submitting it, dismissing the login/safety sheet,
/// stopping the turn in flight, and starting a new chat. Each script
/// returns a JSON status, with diagnostics when it can't find its
/// target.
enum ChatGPTSubmissionScripts {
    static let dismissGate = ChatGPTScript(name: "dismissGate")
    static let insertPrompt = ChatGPTScript(name: "insertPrompt")
    static let sendPrompt = ChatGPTScript(name: "sendPrompt")
    static let startNewChat = ChatGPTScript(name: "startNewChat")
    static let stopStreaming = ChatGPTScript(name: "stopStreaming")
}
