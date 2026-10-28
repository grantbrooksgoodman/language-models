//
//  ChatGPTWebViewHost+Diagnostics.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

extension ChatGPTWebViewHost {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Methods

    func log(
        _ message: String,
        level: LanguageModelLogEntry.Level = .info,
        error: LanguageModelError? = nil,
        fileName: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        LoggingService.log(
            message,
            level: level,
            category: Strings.loggerCategory,
            error: error,
            fileName: fileName,
            function: function,
            line: line
        )
    }

    /// Logs a failure, with the page's state and the bridge's
    /// diagnostics at the debug level.
    func logDiagnostics(_ reason: String) async {
        log(
            reason,
            level: .error
        )

        guard LanguageModels.logLevel.includes(.debug) else { return }

        let bridgeDiagnostics = try? await evaluate(ChatGPTBridgeScripts.diagnosticsProbe) as? String
        let pageState = try? await probePageState()
        log(
            "Page state: \(pageState.map { String(describing: $0) } ?? "unavailable"). Bridge: \(bridgeDiagnostics ?? "unavailable")",
            level: .debug
        )
    }

    func logIgnoredStream(_ message: ChatGPTBridgeMessage) {
        let generation = message.generation.map(String.init) ?? "none"
        log("Ignored a stream message of generation \(generation) during turn \(events.turnGeneration).")
    }

    /// Logs the links in a reply read from the page, so a citation
    /// chip that reaches the reply can be identified by its markup.
    func logLinks(in renderedReply: ChatGPTRenderedReply) {
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

        log(
            "Links in the reply read from the page: \(descriptions.joined(separator: "; "))",
            level: .debug
        )
    }

    func logStream(_ message: ChatGPTBridgeMessage) {
        switch message {
        case let .completed(completion):
            let detail = completion.isFullTextIncomplete ? ", incomplete" : ""
            log("Stream completed for turn \(events.turnGeneration): \(completion.fullText.count) chars from \(completion.textSource)\(detail).")

        case .pageState:
            break

        case .started:
            log("Stream started for turn \(events.turnGeneration).")
        }
    }
}
