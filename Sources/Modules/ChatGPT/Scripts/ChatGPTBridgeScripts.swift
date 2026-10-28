//
//  ChatGPTBridgeScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The injected JavaScript that intercepts the mobile-web conversation
/// stream and reads the page's DOM state.
enum ChatGPTBridgeScripts {
    static let diagnosticsProbe = ChatGPTScript(name: "diagnosticsProbe")

    /// Injected at document start (main frame), composed from the
    /// fragments `manifest.json` lists. Wraps `window.fetch`, and for
    /// any POST whose response is a mobile-web conversation stream,
    /// tees the body, posts to native when the stream starts, and
    /// posts the assistant reply once the stream completes. Recent
    /// POST responses and the shape of the last stream are kept for
    /// ``diagnosticsProbe``.
    static let fetchInterceptor = ChatGPTScript(name: "fetchInterceptor")

    static let pageStateProbe = ChatGPTScript(name: "pageStateProbe")
}
