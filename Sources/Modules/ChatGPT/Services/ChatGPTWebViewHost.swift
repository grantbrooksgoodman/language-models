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

    /// The page state and the current turn's stream events, waited on
    /// by every readiness, submission, and reply step.
    let events = ChatGPTPageEventService()

    /// The last assistant message of the last successful turn.
    private(set) var anchorMessageID: String?

    private(set) var conversationID: String?
    private(set) var conversationURL: URL?
    private(set) var isConversationActive = false
    private(set) var isPageStateLost = false
    private(set) var isTurnInFlight = false

    /// The error of the last navigation that failed, until a navigation
    /// starts or finishes.
    private(set) var lastNavigationError: (any Error)?

    private static let dataStoreIdentifier = UUID(uuidString: Strings.dataStoreIdentifier)!

    /// One persistent data store shared by every host, so all concurrent
    /// chats share a single browser session (cookies/cache/local storage).
    private static let sharedDataStore = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)

    private(set) var webView: StaticWebView?

    // MARK: - Computed Properties

    var currentURL: URL? {
        webView?.url
    }

    var isLoading: Bool {
        webView?.isLoading ?? false
    }

    // MARK: - Init

    override init() {
        super.init()
        events.refresh = { [weak self] in
            try? await self?.probePageState()
        }
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

    func beginTurn() {
        isTurnInFlight = true
        events.beginTurn()
    }

    func clearConversation() {
        anchorMessageID = nil
        conversationID = nil
        conversationURL = nil
        isConversationActive = false
        isPageStateLost = false
    }

    func endTurn() {
        isTurnInFlight = false
        events.endTurn()
    }

    func evaluate(
        _ script: ChatGPTScript,
        arguments: [String: Any] = [:]
    ) async throws(LanguageModelError) -> Any? {
        guard let source = ChatGPTScriptResources.source(for: script) else {
            throw .javaScriptEvaluationFailed("The script resource \(script.name) is missing.")
        }

        // A turn in flight never gets a replacement web view; it is
        // interrupted instead.
        guard let webView = isTurnInFlight ? webView : ensureWebView() else {
            throw .interrupted
        }

        assert(
            Set(arguments.keys) == Set(ChatGPTScriptResources.arguments(for: script)),
            "The arguments of \(script.name) differ from its manifest entry."
        )

        do {
            return try await webView.callAsyncJavaScript(
                source,
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
        lastNavigationError = nil
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

    func probeRenderedReply(
        messageID: String?,
        since transcript: ChatGPTTranscriptState?
    ) async -> ChatGPTRenderedReply? {
        guard messageID != nil || transcript != nil else { return nil }

        return await evaluateJSON(
            ChatGPTTranscriptScripts.renderedReply,
            arguments: [
                "baselineMessageID": transcript?.lastAssistantMessageID ?? "",
                "hasBaseline": transcript != nil,
                "messageID": messageID ?? "",
            ]
        )
    }

    func probeTranscript(
        anchorMessageID: String? = nil
    ) async -> ChatGPTTranscriptState? {
        await evaluateJSON(
            ChatGPTTranscriptScripts.transcriptProbe,
            arguments: ["anchorMessageID": anchorMessageID ?? ""]
        )
    }

    func recordConversation() async {
        isConversationActive = true

        if let transcript = await probeTranscript(),
           let lastAssistantMessageID = transcript.lastAssistantMessageID {
            anchorMessageID = lastAssistantMessageID
        }

        if let pageState = try? await probePageState(),
           let urlConversationID = pageState.urlConversationID {
            conversationID = urlConversationID
            conversationURL = currentURL
        }
    }

    func reload() {
        guard let webView,
              webView.url != nil else {
            return load()
        }

        lastNavigationError = nil
        webView.reload()
    }
}

private extension ChatGPTWebViewHost {
    // MARK: - Properties

    var windowBounds: CGRect {
        UIApplication.shared.mainWindow?.bounds ?? UIApplication.shared.mainScreen.bounds
    }

    // MARK: - Methods

    func buildWebView() -> StaticWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.sharedDataStore

        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        for script in ChatGPTScripts.documentStartScripts + [ChatGPTBridgeScripts.fetchInterceptor] {
            guard let source = ChatGPTScriptResources.source(for: script) else { continue }
            configuration.userContentController.addUserScript(.init(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

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

    func evaluateJSON<Value: Decodable>(
        _ script: ChatGPTScript,
        arguments: [String: Any] = [:]
    ) async -> Value? {
        guard let json = try? await evaluate(
            script,
            arguments: arguments
        ) as? String,
            let data = json.data(using: .utf8) else { return nil }

        return try? JSONDecoder().decode(
            Value.self,
            from: data
        )
    }

    func teardownWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        events.notify()
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

    // MARK: - Did Start Provisional Navigation

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        lastNavigationError = nil
        events.notify()
    }

    // MARK: - Did Finish

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        lastNavigationError = nil
        events.notify()
    }

    // MARK: - Did Fail

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard !isNavigationCancellation(error) else { return }
        lastNavigationError = error
        events.notify()
    }

    // MARK: - Did Fail Provisional Navigation

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard !isNavigationCancellation(error) else { return }
        lastNavigationError = error
        events.notify()
    }

    // MARK: - Web Content Process Did Terminate

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        teardownWebView()
        if isConversationActive {
            isPageStateLost = true
        }

        if isTurnInFlight {
            events.interruptTurn()
        }
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

        guard events.receive(bridgeMessage) else {
            return logIgnoredStream(bridgeMessage)
        }
    }
}
