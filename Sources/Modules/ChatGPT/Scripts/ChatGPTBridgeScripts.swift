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
      window.__chatGPTBridge = {};

      function post(message) {
        try {
          window.webkit.messageHandlers.\(Strings.bridgeMessageHandlerName).postMessage(JSON.stringify(message));
        } catch {}
      }

      function decodeEntities(string) {
        return string.split('&quot;').join('"').split('&#39;').join("'").split('&lt;').join('<').split('&gt;').join('>').split('&amp;').join('&');
      }

      function stripTags(html) {
        var text = "";
        var depth = 0;
        for (var i = 0; i < html.length; i++) {
          var character = html.charAt(i);
          if (character === '<') { depth++; }
          else if (character === '>') { if (depth > 0) { depth--; } }
          else if (depth === 0) { text += character; }
        }
        return decodeEntities(text);
      }

      function joinByIndex(blocksByIndex) {
        var indices = Object.keys(blocksByIndex).map(Number).sort(function(first, second){ return first - second; });
        var segments = [];
        for (var i = 0; i < indices.length; i++) { segments.push(stripTags(blocksByIndex[indices[i]]).trim()); }
        return segments.join('\\n\\n');
      }

      // Committed blocks carry the finalized content of each paragraph,
      // whatever its tag (so code blocks and other formatting are included):
      // <?start name="…-committed-block-N">CONTENT<?end>.
      function extractCommitted(html) {
        var committedBlockLabel = 'committed-block-';
        var pieces = html.split('<?start name="');
        var contentByIndex = {};
        var found = false;
        for (var i = 1; i < pieces.length; i++) {
          var piece = pieces[i];
          var nameEnd = piece.indexOf('"');
          if (nameEnd < 0) { continue; }
          var labelIndex = piece.indexOf(committedBlockLabel);
          if (labelIndex < 0 || labelIndex > nameEnd) { continue; }
          var tagEnd = piece.indexOf('>', nameEnd);
          if (tagEnd < 0) { continue; }
          var contentEnd = piece.indexOf('<?end>', tagEnd);
          if (contentEnd < 0) { continue; }
          contentByIndex[piece.slice(labelIndex + committedBlockLabel.length, nameEnd)] = piece.slice(tagEnd + 1, contentEnd);
          found = true;
        }
        return found ? joinByIndex(contentByIndex) : "";
      }

      // Pending blocks cover only `<p>` content; used as a fallback when
      // no committed blocks are present.
      function extractPending(html) {
        var pieces = html.split('data-assistant-stream-block-index="');
        var contentByIndex = {};
        for (var i = 1; i < pieces.length; i++) {
          var piece = pieces[i];
          var quoteEnd = piece.indexOf('"');
          if (quoteEnd < 0) { continue; }
          var tagEnd = piece.indexOf('>', quoteEnd);
          if (tagEnd < 0) { continue; }
          var contentEnd = piece.indexOf('</p>', tagEnd);
          if (contentEnd < 0) { continue; }
          contentByIndex[piece.slice(0, quoteEnd)] = piece.slice(tagEnd + 1, contentEnd);
        }
        return joinByIndex(contentByIndex);
      }

      function extractAssistantText(html) {
        return extractCommitted(html) || extractPending(html);
      }

      function readMWeb(stream) {
        var reader = stream.getReader();
        var decoder = new TextDecoder();
        var buffer = "";
        var completed = false;

        function finish() {
          if (completed) { return; }
          completed = true;
          post({ type: 'completed', fullText: extractAssistantText(buffer) });
        }

        function pump() {
          reader.read().then(function(result){
            if (result.done) { return finish(); }
            buffer += decoder.decode(result.value, { stream: true });
            if (buffer.indexOf('data-conversation-control="message-stream-complete"') !== -1) { return finish(); }
            pump();
          }).catch(function(){});
        }
        pump();
      }

      var originalFetch = window.fetch;
      window.fetch = function(input, init) {
        var method = (((init && init.method) || (input && input.method) || 'GET') + '').toUpperCase();

        var promise = originalFetch.apply(this, arguments);
        if (method !== 'POST') { return promise; }

        return promise.then(function(response){
          try {
            var contentType = (response.headers && response.headers.get && response.headers.get('content-type')) || '';
            if (contentType.indexOf('openai.web-mobile-partial') === -1) { return response; }

            if (!response.body || !response.body.tee) { return response; }
            var teedStreams = response.body.tee();
            readMWeb(teedStreams[1]);
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
    return JSON.stringify({
      isChallengePresent: hasChallenge,
      isComposerPresent: !!(select('#mobile-composer-prompt') || select('textarea[name="prompt"]')),
      isLoggedOutModalPresent: !!select('[data-conversation-gate-panel]'),
      isStreaming: !!select('[data-testid="stop-button"]'),
      urlConversationID: conversationID
    });
    """
}
