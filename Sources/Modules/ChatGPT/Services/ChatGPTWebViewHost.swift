//
//  ChatGPTWebViewHost.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation
import UIKit

@preconcurrency import WebKit

@MainActor
final class ChatGPTWebViewHost: NSObject {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    nonisolated static let baseURL = URL(string: Strings.baseURLString)!

    private static let dataStoreIdentifier = UUID(uuidString: Strings.dataStoreIdentifier)!

    /// One persistent data store shared by every host, so all concurrent
    /// chats share a single browser session (cookies/cache/local storage).
    private static let sharedDataStore = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)

    private var bridgeContinuations = [UUID: AsyncStream<ChatGPTBridgeMessage>.Continuation]()
    private var webView: StaticWebView?

    // MARK: - Computed Properties

    var currentURL: URL? {
        webView?.url
    }

    // MARK: - Init

    override init() {
        super.init()
    }

    deinit {
        // The web view is added as a window subview, which retains it,
        // so it is detached on release to avoid accumulating off-screen
        // across requests. The host may be released off the main thread,
        // so the UIKit teardown runs on the main actor.
        guard let webView else { return }
        let releasedWebView = webView
        Task { @MainActor in
            releasedWebView.stopLoading()
            releasedWebView.navigationDelegate = nil
            releasedWebView.removeFromSuperview()
        }
    }

    // MARK: - Methods

    func bridgeMessages() -> AsyncStream<ChatGPTBridgeMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            bridgeContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.bridgeContinuations[id] = nil }
            }
        }
    }

    func evaluate(
        _ script: String,
        arguments: [String: Any] = [:]
    ) async throws(LanguageModelError) -> Any? {
        let webView = ensureWebView()
        do {
            return try await webView.callAsyncJavaScript(
                script,
                arguments: arguments,
                contentWorld: .page
            )
        } catch {
            throw .javaScriptEvaluationFailed(error.localizedDescription)
        }
    }

    func load(_ url: URL = ChatGPTWebViewHost.baseURL) {
        let webView = ensureWebView()
        guard webView.url != url else { return }
        webView.load(.init(url: url))
    }

    func probePageState() async throws(LanguageModelError) -> ChatGPTPageState {
        guard let json = try await evaluate(ChatGPTBridgeScripts.pageStateProbe) as? String,
              let data = json.data(using: .utf8) else {
            throw .pageStateUnavailable
        }

        guard let pageState = try? JSONDecoder().decode(
            ChatGPTPageState.self,
            from: data
        ) else {
            throw .pageStateUnavailable
        }

        return pageState
    }

    func reload() {
        guard let webView,
              webView.url != nil else {
            return load()
        }

        webView.reload()
    }
}

private extension ChatGPTWebViewHost {
    // MARK: - Computed Properties

    var windowBounds: CGRect {
        UIApplication.shared.mainWindow?.bounds ?? UIApplication.shared.mainScreen.bounds
    }

    // MARK: - Web View Lifecycle

    @discardableResult
    func ensureWebView() -> StaticWebView {
        if let webView {
            // Re-attach if the web view was built before a window existed;
            // an off-window web view is throttled and may never finish loading.
            if webView.window == nil {
                UIApplication.shared.mainWindow?.addSubview(webView)
            }

            return webView
        }

        let webView = buildWebView()
        self.webView = webView
        UIApplication.shared.mainWindow?.addSubview(webView)
        return webView
    }

    func buildWebView() -> StaticWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.sharedDataStore

        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        for script in ChatGPTScripts.documentStartScripts {
            configuration.userContentController.addUserScript(.init(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        configuration.userContentController.addUserScript(.init(
            source: ChatGPTBridgeScripts.fetchInterceptor,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: Strings.bridgeMessageHandlerName
        )

        ChatGPTContentRules.install(on: configuration.userContentController)

        let webView = StaticWebView(
            frame: windowBounds,
            configuration: configuration
        )

        webView.alpha = 0
        webView.customUserAgent = Strings.desktopUserAgent
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = self

        #if DEBUG
        webView.isInspectable = true
        #endif

        return webView
    }

    func teardownWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }
}

extension ChatGPTWebViewHost: WKNavigationDelegate {
    // MARK: - Create Web View with Configuration

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    // MARK: - Web Content Process Did Terminate

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        teardownWebView()
    }
}

extension ChatGPTWebViewHost: WKScriptMessageHandler {
    // MARK: - Did Receive Script Message

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Strings.bridgeMessageHandlerName,
              let json = message.body as? String,
              let data = json.data(using: .utf8),
              let bridgeMessage = try? JSONDecoder().decode(
                  ChatGPTBridgeMessage.self,
                  from: data
              ) else { return }

        for continuation in bridgeContinuations.values {
            continuation.yield(bridgeMessage)
        }
    }
}
