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
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    static let diagnosticsProbe = """
    var bridge = window.__chatGPTBridge;
    if (!bridge) { return JSON.stringify({ isInstalled: false }); }

    function sortedKeys(keys) { return keys ? Object.keys(keys).sort() : undefined; }

    var stream = bridge.lastStream;
    return JSON.stringify({
      isInstalled: true,
      lastStream: stream ? {
        ageSeconds: Math.round((Date.now() - stream.startDate) / 1000),
        contentKeys: sortedKeys(stream.contentKeys),
        contentType: stream.contentType,
        dilKeys: sortedKeys(stream.dilKeys),
        eventTypes: stream.eventTypes,
        length: stream.length,
        referenceKeys: sortedKeys(stream.referenceKeys),
        textSource: stream.textSource,
        versions: sortedKeys(stream.versions)
      } : null,
      recentResponses: bridge.recentResponses
    });
    """

    /// Injected at document start (main frame). Wraps `window.fetch`, and
    /// for any POST whose response is a mobile-web conversation stream,
    /// tees the body, posts to native when the stream starts, and posts
    /// the assistant reply once the stream completes. Recent POST
    /// responses and the shape of the last stream are kept for
    /// ``diagnosticsProbe``.
    static let fetchInterceptor = """
    (function(){
      if (window.__chatGPTBridge) { return; }
      var bridge = window.__chatGPTBridge = { lastStream: null, recentResponses: [] };

      function post(message) {
        try {
          window.webkit.messageHandlers.\(Strings.bridgeMessageHandlerName).postMessage(JSON.stringify(message));
        } catch {}
      }

    \(ChatGPTMarkdownScripts.unescaper)

    \(ChatGPTStreamReaderScripts.conversationSourceReader)

    \(ChatGPTStreamReaderScripts.partialHTMLReader)

      function streamReader(contentType) {
        if (contentType.indexOf('openai.conversation-source') !== -1) { return readConversationSource; }
        if (contentType.indexOf('openai.web-mobile-partial') !== -1) { return readPartialHTML; }
        return null;
      }

      function recordResponse(input, response, contentType, isConversationStream) {
        if (response.status === 204) { return; }
        var url = ((input && input.url) || input) + '';
        bridge.recentResponses.push({
          contentType: contentType, isConversationStream: isConversationStream, path: url.split('?')[0], status: response.status
        });
        if (bridge.recentResponses.length > 20) { bridge.recentResponses.shift(); }
      }

      var originalFetch = window.fetch;
      window.fetch = function(input, init) {
        var method = (((init && init.method) || (input && input.method) || 'GET') + '').toUpperCase();

        var promise = originalFetch.apply(this, arguments);
        if (method !== 'POST') { return promise; }

        return promise.then(function(response){
          try {
            var contentType = (response.headers && response.headers.get && response.headers.get('content-type')) || '';
            var readStream = streamReader(contentType);
            recordResponse(input, response, contentType, !!readStream);
            if (!readStream) { return response; }

            if (!response.body || !response.body.tee) { return response; }
            var teedStreams = response.body.tee();
            post({ type: 'started' });
            readStream(teedStreams[1], contentType);
            return new Response(teedStreams[0], response);
          } catch { return response; }
        });
      };
    })();
    """

    /// A function body (for `callAsyncJavaScript`) that returns the page
    /// state as a JSON string.
    static let pageStateProbe = """
    function select(selector) { return document.querySelector(selector); }
    var pathComponents = location.pathname.split('/').filter(Boolean);
    var conversationID = (pathComponents.length >= 2 && (pathComponents[0] === 'c' || pathComponents[0] === 'uc')) ? pathComponents[1] : null;
    var hasChallenge = !!document.querySelector('iframe[src*="challenges.cloudflare.com"]')
                    || /just a moment/i.test(document.title || "");
    // The mobile-web composer marks its form while a turn is in flight
    // (its send button acts as a stop button), and the assistant
    // message while it streams.
    var isStreaming = !!(select('[data-testid="stop-button"]')
                    || select('form[data-octane-followup-submitting]')
                    || select('[data-message-role="assistant"][data-message-streaming]'));
    return JSON.stringify({
      isChallengePresent: hasChallenge,
      isComposerPresent: !!(select('#mobile-composer-prompt') || select('textarea[name="prompt"]')),
      isLoggedOutModalPresent: !!select('[data-conversation-gate-panel]'),
      isStreaming: isStreaming,
      urlConversationID: conversationID
    });
    """
}
