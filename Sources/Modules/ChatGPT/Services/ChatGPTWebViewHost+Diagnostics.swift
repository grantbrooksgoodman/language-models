//
//  ChatGPTWebViewHost+Diagnostics.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation
import os

extension ChatGPTWebViewHost {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    #if DEBUG
    private static let logger = Logger(
        subsystem: Strings.loggerSubsystem,
        category: Strings.loggerCategory
    )
    #endif

    // MARK: - Methods

    func logDiagnostics(_ reason: String) async {
        #if DEBUG
        // Neither the prompt nor the reply is logged.
        let bridgeDiagnostics = try? await evaluate(ChatGPTBridgeScripts.diagnosticsProbe) as? String
        let pageState = try? await probePageState()

        let message = [
            reason,
            "Page state: \(pageState.map { String(describing: $0) } ?? "unavailable").",
            "Bridge: \(bridgeDiagnostics ?? "unavailable")",
        ].joined(separator: " ")

        Self.logger.warning("\(message, privacy: .public)")
        #endif
    }

    func logIgnoredStream(_ message: ChatGPTBridgeMessage) {
        #if DEBUG
        let generation = message.generation.map(String.init) ?? "none"
        let turn = String(events.turnGeneration)
        Self.logger.warning("Ignored a stream message of generation \(generation, privacy: .public) during turn \(turn, privacy: .public).")
        #endif
    }

    /// Logs the links in a reply read from the page, so a citation
    /// chip that reaches the reply can be identified by its markup.
    func logLinks(in renderedReply: ChatGPTRenderedReply) {
        #if DEBUG
        guard !renderedReply.linkDescriptors.isEmpty else { return }

        let descriptions = renderedReply.linkDescriptors.map { descriptor in
            [
                descriptor.isChip ? "skipped" : "kept",
                descriptor.tag,
                "display=\(descriptor.display)",
                "textLength=\(descriptor.textLength)",
                descriptor.attributes.joined(separator: " "),
            ].joined(separator: " ")
        }

        Self.logger.warning("Links in the reply read from the page: \(descriptions.joined(separator: "; "), privacy: .public)")
        #endif
    }
}
