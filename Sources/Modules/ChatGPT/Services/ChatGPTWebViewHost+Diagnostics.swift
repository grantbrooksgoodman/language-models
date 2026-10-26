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
}
