//
//  ChatGPTStreamReaderScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The injected JavaScript that parses the mobile-web conversation
/// reply.
///
/// The logged-out iOS web view is served the mobile-web (`unauth-mweb`)
/// experience, whose conversation response streams in one of two
/// formats:
///
/// - `application/vnd.openai.conversation-source+ndjson` – newline-
///   delimited JSON events; an `end` event closes the stream. Each
///   `content` event carries its message's text in `markdown`, which
///   replaces or appends to the message according to the event's
///   `mode`, and in `dil.fallbackMarkdown`, a rendering of the whole
///   message so far whose text is escaped as in CommonMark. The reply
///   is read from `markdown` when it is non-empty, and otherwise from
///   the unescaped rendering.
/// - `text/vnd.openai.web-mobile-partial+html` – a sequence of
///   `<template>` frames. The reply text lives in
///   `<p data-assistant-stream-block-index="N">` blocks; completion
///   arrives as a `data-conversation-control` island.
enum ChatGPTStreamReaderScripts {
    static let conversationSourceReader = """
    // Reads the NDJSON conversation-source stream. A `content` event
    // replaces its message's markdown, or appends to it when its
    // `mode` is `append`, and carries a `fallbackMarkdown` rendering
    // of the whole message so far, and the `references` its sources
    // cite. The reply is the latest message to change: its markdown
    // if non-empty, else its unescaped rendering, which omits the
    // content of any components the message requires and renders a
    // source citation as its label. The labels of the message's
    // references are posted with the reply so they can be stripped.
    function readConversationSource(stream, contentType) {
      var reader = stream.getReader();
      var decoder = new TextDecoder();
      var buffer = "";
      var completed = false;
      var citationLabelsByMessageID = {};
      var fallbackMarkdownByMessageID = {};
      var hasLinksByMessageID = {};
      var latestMessageID = null;
      var markdownByMessageID = {};
      var requiredComponentsByMessageID = {};
      var shape = bridge.lastStream = {
        contentKeys: {}, contentType: contentType, dilKeys: {}, eventTypes: {}, referenceKeys: {}, startDate: Date.now(), textSource: null, versions: {}
      };

      function recordKeys(keys, object) {
        if (object && typeof object === 'object') { Object.keys(object).forEach(function(key){ keys[key] = true; }); }
      }

      // Collects every short string in a reference – and the host of
      // every URL – as a label a citation may be rendered with.
      function collectLabels(value, labels, depth) {
        if (depth > 6 || value === null || value === undefined) { return; }
        if (typeof value === 'string') {
          var text = value.trim();
          if (!text || text.length > 120) { return; }
          if (/^https?:/i.test(text)) {
            try { var host = new URL(text).hostname; labels[host] = true; labels[host.replace(/^www\\./, '')] = true; } catch {}
            return;
          }
          labels[text] = true;
        } else if (Array.isArray(value)) {
          value.forEach(function(element){ collectLabels(element, labels, depth + 1); });
        } else if (typeof value === 'object') {
          recordKeys(shape.referenceKeys, value);
          Object.keys(value).forEach(function(key){ collectLabels(value[key], labels, depth + 1); });
        }
      }

      function finish() {
        if (completed) { return; }
        completed = true;
        var markdown = latestMessageID === null ? "" : (markdownByMessageID[latestMessageID] || "").trim();
        var fallbackMarkdown = latestMessageID === null ? "" : unescapeMarkdown(fallbackMarkdownByMessageID[latestMessageID] || "").trim();
        var requiredComponents = (latestMessageID !== null && requiredComponentsByMessageID[latestMessageID]) || [];
        var citationLabels = Object.keys((latestMessageID !== null && citationLabelsByMessageID[latestMessageID]) || {});
        var hasLinks = latestMessageID !== null && !!hasLinksByMessageID[latestMessageID];
        shape.textSource = markdown ? 'markdown' : (fallbackMarkdown ? 'fallbackMarkdown' : 'none');
        // A rendering with links is read from the page, which marks
        // its citations; the rendering shows them as plain labels.
        post({
          citationLabels: citationLabels,
          fullText: markdown || fallbackMarkdown,
          isFullTextIncomplete: !markdown && (requiredComponents.length > 0 || citationLabels.length > 0 || hasLinks),
          messageID: latestMessageID,
          type: 'completed'
        });
      }

      function handleLine(line) {
        var event;
        try { event = JSON.parse(line); } catch { return; }
        if (!event || typeof event !== 'object') { return; }
        shape.eventTypes[event.type] = (shape.eventTypes[event.type] || 0) + 1;
        if (event.version !== undefined) { shape.versions[event.version] = true; }
        if (event.type === 'end') { return finish(); }
        if (event.type !== 'content' || typeof event.messageId !== 'string') { return; }

        recordKeys(shape.contentKeys, event);
        recordKeys(shape.dilKeys, event.dil);
        var messageID = event.messageId;
        latestMessageID = messageID;
        if (typeof event.markdown === 'string') {
          var priorMarkdown = event.mode === 'append' ? (markdownByMessageID[messageID] || "") : "";
          markdownByMessageID[messageID] = priorMarkdown + event.markdown;
        }
        if (event.dil && typeof event.dil.fallbackMarkdown === 'string') {
          fallbackMarkdownByMessageID[messageID] = event.dil.fallbackMarkdown;
        }
        if (event.dil && Array.isArray(event.dil.requiredComponents)) {
          requiredComponentsByMessageID[messageID] = event.dil.requiredComponents;
        }
        if (event.dil && /https?:\\/\\//i.test(JSON.stringify(event.dil))) {
          hasLinksByMessageID[messageID] = true;
        }
        if (event.references !== undefined && event.references !== null) {
          var labels = citationLabelsByMessageID[messageID] || (citationLabelsByMessageID[messageID] = {});
          collectLabels(event.references, labels, 0);
        }
      }

      function pump() {
        reader.read().then(function(result){
          if (result.done) {
            handleLine(buffer + decoder.decode());
            return finish();
          }
          buffer += decoder.decode(result.value, { stream: true });
          var lines = buffer.split('\\n');
          buffer = lines.pop();
          for (var i = 0; i < lines.length && !completed; i++) { handleLine(lines[i]); }
          if (!completed) { pump(); }
        }).catch(function(){});
      }
      pump();
    }
    """

    static let partialHTMLReader = """
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

    function readPartialHTML(stream, contentType) {
      var reader = stream.getReader();
      var decoder = new TextDecoder();
      var buffer = "";
      var completed = false;
      var shape = bridge.lastStream = { contentType: contentType, length: 0, startDate: Date.now(), textSource: null };

      function finish() {
        if (completed) { return; }
        completed = true;
        var text = extractAssistantText(buffer);
        shape.length = buffer.length;
        shape.textSource = text ? 'partialHTML' : 'none';
        post({ citationLabels: [], fullText: text, isFullTextIncomplete: false, messageID: null, type: 'completed' });
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
    """
}
