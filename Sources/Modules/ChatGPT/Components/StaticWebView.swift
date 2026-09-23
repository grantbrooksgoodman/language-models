//
//  StaticWebView.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import UIKit

@preconcurrency import WebKit

/// A `WKWebView` that suppresses text input, keeping the keyboard from
/// appearing while the web view runs off-screen.
final class StaticWebView: WKWebView {
    override var canBecomeFirstResponder: Bool {
        false
    }

    override var inputAccessoryView: UIView? {
        UIView(frame: .zero)
    }

    override var inputView: UIView? {
        UIView(frame: .zero)
    }
}
