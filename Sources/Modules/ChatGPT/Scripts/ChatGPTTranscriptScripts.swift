//
//  ChatGPTTranscriptScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

enum ChatGPTTranscriptScripts {
    static let renderedReply = """
    // Takes `baselineMessageID`, `hasBaseline`, and `messageID`
    // arguments. Finds the reply by `messageID`, or else, given a
    // baseline, as the latest assistant message other than the one
    // that was latest at the baseline. Its text is read once the page
    // marks it complete, as plain text with fenced code blocks.
    var blockTags = [
      'ADDRESS', 'ARTICLE', 'ASIDE', 'BLOCKQUOTE', 'DD', 'DETAILS', 'DIV', 'DL', 'DT', 'FIGCAPTION', 'FIGURE', 'FOOTER',
      'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEADER', 'HR', 'LI', 'MAIN', 'OL', 'P', 'PRE', 'SECTION', 'TABLE', 'UL'
    ];
    var skippedTags = ['BUTTON', 'NOSCRIPT', 'SCRIPT', 'STYLE', 'SVG', 'TEMPLATE'];

    function tagName(element) { return element.tagName.toUpperCase(); }

    function childElements(element) { return Array.prototype.slice.call(element.children); }

    // A source citation chip: a link carrying a favicon, an element
    // marked as a citation, or a "+N" sources badge.
    function isCitationChip(element) {
      if (tagName(element) === 'A' && element.querySelector('img')) { return true; }
      for (var i = 0; i < element.attributes.length; i++) {
        if (/citation|cite/i.test(element.attributes[i].name)) { return true; }
      }
      return /^\\+\\d+$/.test((element.textContent || '').trim());
    }

    function isSkipped(element) {
      if (skippedTags.indexOf(tagName(element)) !== -1 || element.hidden) { return true; }
      if (element.getAttribute('aria-hidden') === 'true' || element.getAttribute('role') === 'status') { return true; }
      if (element.hasAttribute('data-message-content-controls') || isCitationChip(element)) { return true; }
      var style = getComputedStyle(element);
      return style.display === 'none' || style.visibility === 'hidden';
    }

    // Collapses whitespace as rendering does, unless the parent
    // preserves it.
    function nodeText(node) {
      var text = node.nodeValue.split(String.fromCharCode(160)).join(' ');
      var whiteSpace = node.parentElement ? getComputedStyle(node.parentElement).whiteSpace : '';
      return /^(pre|break-spaces)/.test(whiteSpace) ? text : text.replace(/\\s+/g, ' ');
    }

    function inlineText(node) {
      if (node.nodeType === 3) { return nodeText(node); }
      if (node.nodeType !== 1 || isSkipped(node)) { return ''; }
      if (tagName(node) === 'BR') { return '\\n'; }
      var text = '';
      for (var i = 0; i < node.childNodes.length; i++) { text += inlineText(node.childNodes[i]); }
      // A link's text is followed by a space before its icon.
      return tagName(node) === 'A' ? text.trim() : text;
    }

    function codeBlockText(pre) {
      return '```\\n' + pre.textContent.replace(/\\n+$/, '') + '\\n```';
    }

    // A code block's wrapper holds its copy control and language label
    // beside its `pre`.
    function isCodeBlockWrapper(element) {
      var children = childElements(element);
      var preCount = children.filter(function(child){ return tagName(child) === 'PRE'; }).length;
      return preCount === 1 && children.every(function(child){ return ['DIV', 'PRE', 'SPAN'].indexOf(tagName(child)) !== -1; });
    }

    function listText(list) {
      var isOrdered = tagName(list) === 'OL';
      var start = parseInt(list.getAttribute('start'), 10) || 1;
      var items = childElements(list).filter(function(item){ return tagName(item) === 'LI' && !isSkipped(item); });
      return items.map(function(item, index){
        var marker = isOrdered ? (start + index) + '. ' : '- ';
        return marker + blocks(item).join('\\n').split('\\n').join('\\n' + ' '.repeat(marker.length));
      }).join('\\n');
    }

    function tableText(table) {
      return Array.prototype.map.call(table.querySelectorAll('tr'), function(row){
        var cells = childElements(row).filter(function(cell){ return tagName(cell) === 'TD' || tagName(cell) === 'TH'; });
        return cells.map(function(cell){ return blocks(cell).join(' '); }).join(' | ');
      }).join('\\n');
    }

    function blocks(element) {
      var tag = tagName(element);
      if (tag === 'PRE') { return [codeBlockText(element)]; }
      if (isCodeBlockWrapper(element)) { return [codeBlockText(element.querySelector(':scope > pre'))]; }
      if (tag === 'OL' || tag === 'UL') { return [listText(element)]; }
      if (tag === 'TABLE') { return [tableText(element)]; }

      var result = [];
      var inline = '';
      for (var i = 0; i < element.childNodes.length; i++) {
        var child = element.childNodes[i];
        if (child.nodeType === 1 && !isSkipped(child) && blockTags.indexOf(tagName(child)) !== -1) {
          if (inline.trim()) { result.push(inline.trim()); }
          inline = '';
          result = result.concat(blocks(child));
        } else {
          inline += inlineText(child);
        }
      }
      if (inline.trim()) { result.push(inline.trim()); }
      return result;
    }

    var message = messageID ? document.getElementById(messageID) : null;
    if (!message && hasBaseline) {
      var messages = document.querySelectorAll('[data-message-role="assistant"]');
      var latest = messages.length ? messages[messages.length - 1] : null;
      if (latest && latest.id && latest.id !== baselineMessageID) { message = latest; }
    }

    var root = message ? message.querySelector('[data-assistant-markdown-root]') : null;
    var isComplete = !!message && message.hasAttribute('data-message-complete');
    return JSON.stringify({
      isComplete: isComplete,
      messageID: message ? (message.id || null) : null,
      text: isComplete && root ? blocks(root).join('\\n\\n') : ''
    });
    """

    static let transcriptProbe = """
    function lastMessageID(role) {
      var messages = document.querySelectorAll('[data-message-role="' + role + '"]');
      return messages.length ? (messages[messages.length - 1].id || null) : null;
    }

    var composer = document.querySelector('#mobile-composer-prompt')
                || document.querySelector('textarea[name="prompt"]')
                || document.querySelector('div[contenteditable="true"]')
                || document.querySelector('textarea');
    var composerText = composer ? (typeof composer.value === 'string' ? composer.value : composer.innerText) : '';
    return JSON.stringify({
      composerText: composerText || '',
      lastAssistantMessageID: lastMessageID('assistant'),
      lastUserMessageID: lastMessageID('user')
    });
    """
}
