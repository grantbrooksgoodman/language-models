//
//  ChatGPTContentRules.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

@preconcurrency import WebKit

/// `WKContentRuleList`s that block assets the reply does not need –
/// images, media, and custom fonts – to speed up page loads. Each list
/// ends with a rule that exempts Cloudflare challenge resources, so a
/// challenge can still render if one appears. The lists are compiled
/// once per launch and cached.
@MainActor
enum ChatGPTContentRules {
    // MARK: - Properties

    private static let all: [String: String] = [
        "gpt-no-fonts": noFonts,
        "gpt-no-images": noImages,
    ]

    /// Domain triggers match the main document, which is always
    /// chatgpt.com, so challenge resources are exempted by URL with a
    /// rule that ignores the blocking rule before it. Such a rule only
    /// applies within its own list.
    private static let challengeExemption = #"""
    {
      "trigger": { "url-filter": "^https://challenges\\.cloudflare\\.com/" },
      "action": { "type": "ignore-previous-rules" }
    }
    """#

    private static let noFonts = """
    [{
      "trigger": { "url-filter": ".*", "resource-type": ["font"] },
      "action": { "type": "block" }
    },
    \(challengeExemption)]
    """

    private static let noImages = """
    [{
      "trigger": { "url-filter": ".*", "resource-type": ["image","media"] },
      "action": { "type": "block" }
    },
    \(challengeExemption)]
    """

    private static var compilationTask: Task<Void, Never>?
    private static var compiledRuleLists = [String: WKContentRuleList]()

    // MARK: - Methods

    static func install(on controller: WKUserContentController) {
        var pendingIdentifiers = [String]()
        for identifier in all.keys.sorted() {
            if let ruleList = compiledRuleLists[identifier] {
                controller.add(ruleList)
            } else {
                pendingIdentifiers.append(identifier)
            }
        }

        guard !pendingIdentifiers.isEmpty else { return }

        // A list still compiling is attached once compilation ends.
        Task {
            await waitUntilCompiled()
            for identifier in pendingIdentifiers {
                guard let ruleList = compiledRuleLists[identifier] else { continue }
                controller.add(ruleList)
            }
        }
    }

    static func precompile() {
        guard compilationTask == nil else { return }
        compilationTask = Task {
            guard let store = WKContentRuleListStore.default() else { return }
            for (identifier, rule) in all {
                compiledRuleLists[identifier] = try? await store.compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: rule
                )
            }
        }
    }

    static func waitUntilCompiled() async {
        precompile()
        await compilationTask?.value
    }
}
