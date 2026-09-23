//
//  WeakScriptMessageHandler.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

@preconcurrency import WebKit

/// Proxies script messages through a weak reference, preventing the
/// retain cycle `WKUserContentController` would otherwise create with
/// its handler.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    // MARK: - Properties

    private weak var delegate: (any WKScriptMessageHandler)?

    // MARK: - Init

    init(delegate: any WKScriptMessageHandler) {
        self.delegate = delegate
    }

    // MARK: - Did Receive Script Message

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(
            userContentController,
            didReceive: message
        )
    }
}
