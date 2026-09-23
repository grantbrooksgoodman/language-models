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
/// images, media, and custom fonts – to speed up page loads. Cloudflare
/// challenge frames are exempted so a challenge can still render if one
/// appears.
enum ChatGPTContentRules {
    // MARK: - Properties

    private static let all: [String: String] = [
        "gpt-no-fonts": noFonts,
        "gpt-no-images": noImages,
    ]

    private static let noFonts = """
    [{
      "trigger": { "url-filter": ".*", "resource-type": ["font"], "unless-domain": ["challenges.cloudflare.com","*.cloudflare.com"] },
      "action": { "type": "block" }
    }]
    """

    private static let noImages = """
    [{
      "trigger": { "url-filter": ".*", "resource-type": ["image","media"], "unless-domain": ["challenges.cloudflare.com","*.cloudflare.com"] },
      "action": { "type": "block" }
    }]
    """

    // MARK: - Methods

    @MainActor
    static func install(on controller: WKUserContentController) {
        guard let store = WKContentRuleListStore.default() else { return }
        for (identifier, rule) in all {
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: rule
            ) { list, _ in
                guard let list else { return }
                controller.add(list)
            }
        }
    }
}
