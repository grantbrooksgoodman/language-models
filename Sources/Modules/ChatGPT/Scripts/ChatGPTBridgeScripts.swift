//
//  ChatGPTBridgeScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The injected JavaScript that parses the mobile-web partial-HTML reply
/// and reads the page's DOM state.
///
/// The logged-out iOS web view is served the mobile-web (`unauth-mweb`)
/// experience, whose conversation response streams
/// `text/vnd.openai.web-mobile-partial+html` – a sequence of `<template>`
/// frames rather than JSON SSE. The reply text lives in
/// `<p data-assistant-stream-block-index="N">` blocks; completion arrives
/// as a `data-conversation-control` island.
enum ChatGPTBridgeScripts {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    /// Injected at document start (main frame). Wraps `window.fetch`, and
    /// for any POST whose response is the mobile-web partial-HTML stream,
    /// tees the body, extracts the assistant reply, and posts it to native
    /// once the stream completes.
    static let fetchInterceptor = """
    (function(){
      if (window.__chatGPTBridge) { return; }
      var bridge = window.__chatGPTBridge = { latest: { done: false } };

      function post(msg) {
        try {
          window.webkit.messageHandlers.\(Strings.bridgeMessageHandlerName).postMessage(JSON.stringify(msg));
        } catch (e) {}
      }

      function decodeEntities(s) {
        return s.split('&quot;').join('"').split('&#39;').join("'").split('&lt;').join('<').split('&gt;').join('>').split('&amp;').join('&');
      }

      function stripTags(s) {
        var out = "";
        var depth = 0;
        for (var i = 0; i < s.length; i++) {
          var c = s.charAt(i);
          if (c === '<') { depth++; }
          else if (c === '>') { if (depth > 0) { depth--; } }
          else if (depth === 0) { out += c; }
        }
        return decodeEntities(out);
      }

      function joinByIndex(byIndex) {
        var keys = Object.keys(byIndex).map(Number).sort(function(a, b){ return a - b; });
        var parts = [];
        for (var k = 0; k < keys.length; k++) { parts.push(stripTags(byIndex[keys[k]]).trim()); }
        return parts.join('\\n\\n');
      }

      // Committed blocks carry the finalized content of each paragraph,
      // whatever its tag (so code blocks and other formatting are included):
      // <?start name="…-committed-block-N">CONTENT<?end>.
      function extractCommitted(html) {
        var pieces = html.split('<?start name="');
        var byIndex = {};
        var found = false;
        for (var i = 1; i < pieces.length; i++) {
          var piece = pieces[i];
          var nameEnd = piece.indexOf('"');
          if (nameEnd < 0) { continue; }
          var cb = piece.indexOf('committed-block-');
          if (cb < 0 || cb > nameEnd) { continue; }
          var gt = piece.indexOf('>', nameEnd);
          if (gt < 0) { continue; }
          var end = piece.indexOf('<?end>', gt);
          if (end < 0) { continue; }
          byIndex[piece.slice(cb + 16, nameEnd)] = piece.slice(gt + 1, end);
          found = true;
        }
        return found ? joinByIndex(byIndex) : "";
      }

      // Pending blocks cover only `<p>` content; used as a fallback when
      // no committed blocks are present.
      function extractPending(html) {
        var pieces = html.split('data-assistant-stream-block-index="');
        var byIndex = {};
        for (var i = 1; i < pieces.length; i++) {
          var piece = pieces[i];
          var q = piece.indexOf('"');
          if (q < 0) { continue; }
          var gt = piece.indexOf('>', q);
          if (gt < 0) { continue; }
          var end = piece.indexOf('</p>', gt);
          if (end < 0) { continue; }
          byIndex[piece.slice(0, q)] = piece.slice(gt + 1, end);
        }
        return joinByIndex(byIndex);
      }

      function extractAssistantText(html) {
        return extractCommitted(html) || extractPending(html);
      }

      function readMWeb(stream) {
        var reader = stream.getReader();
        var decoder = new TextDecoder();
        var buffer = "";

        function finish() {
          if (bridge.latest.done) { return; }
          bridge.latest.done = true;
          post({ type: 'completed', fullText: extractAssistantText(buffer) });
        }

        function pump() {
          reader.read().then(function(res){
            if (res.done) { return finish(); }
            buffer += decoder.decode(res.value, { stream: true });
            if (buffer.indexOf('data-conversation-control="message-stream-complete"') !== -1) { return finish(); }
            pump();
          }).catch(function(e){});
        }
        pump();
      }

      var origFetch = window.fetch;
      window.fetch = function(input, init) {
        var method = (((init && init.method) || (input && input.method) || 'GET') + '').toUpperCase();

        var promise = origFetch.apply(this, arguments);
        if (method !== 'POST') { return promise; }

        return promise.then(function(response){
          try {
            var ct = (response.headers && response.headers.get && response.headers.get('content-type')) || '';
            if (ct.indexOf('openai.web-mobile-partial') === -1) { return response; }

            bridge.latest = { done: false };

            if (!response.body || !response.body.tee) { return response; }
            var b = response.body.tee();
            readMWeb(b[1]);
            return new Response(b[0], response);
          } catch (e) { return response; }
        });
      };
    })();
    """

    /// A function body (for `callAsyncJavaScript`) that returns the page
    /// state as a JSON string.
    static let pageStateProbe = """
    function q(s) { return document.querySelector(s); }
    var parts = location.pathname.split('/').filter(Boolean);
    var convID = (parts.length >= 2 && (parts[0] === 'c' || parts[0] === 'uc')) ? parts[1] : null;
    var challenge = !!document.querySelector('iframe[src*="challenges.cloudflare.com"]')
                 || /just a moment/i.test(document.title || "");
    return JSON.stringify({
      isChallengePresent: challenge,
      isComposerPresent: !!(q('#mobile-composer-prompt') || q('textarea[name="prompt"]')),
      isLoggedOutModalPresent: !!q('[data-conversation-gate-panel]'),
      isStreaming: !!q('[data-testid="stop-button"]'),
      urlConversationID: convID
    });
    """
}
