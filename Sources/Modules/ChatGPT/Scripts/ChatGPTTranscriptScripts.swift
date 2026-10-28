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

    var describedLinks = [];
    var linkDescriptors = [];

    function isExternalLink(element) {
      var href = element.getAttribute('href') || '';
      return /^https?:/i.test(href) && !/^https?:\\/\\/([^\\/]*\\.)?(chatgpt|openai)\\.com/i.test(href);
    }

    // A citation is styled as a pill or a dotted link: it, a
    // descendant, or an inline ancestor has rounded corners, an
    // inline-flex or inline-block layout, an icon, ellipsized text, or
    // a dotted or dashed underline.
    function isCitationStyled(element) {
      var elements = [element].concat(Array.prototype.slice.call(element.querySelectorAll('*')));
      for (var ancestor = element.parentElement; ancestor && blockTags.indexOf(tagName(ancestor)) === -1; ancestor = ancestor.parentElement) {
        elements.push(ancestor);
      }
      return elements.some(function(candidate){
        var candidateTag = tagName(candidate);
        if (candidateTag === 'IMG' || candidateTag === 'SVG') { return true; }
        var style = getComputedStyle(candidate);
        return /inline-(flex|block|grid)/.test(style.display)
            || parseFloat(style.borderRadius) > 0
            || style.textOverflow === 'ellipsis'
            || /dotted|dashed/.test(style.textDecorationStyle);
      });
    }

    function describe(element, isChip) {
      var describedIndex = describedLinks.indexOf(element);
      if (describedIndex !== -1) { linkDescriptors[describedIndex].isChip = linkDescriptors[describedIndex].isChip || isChip; return; }
      describedLinks.push(element);
      var attributes = Array.prototype.map.call(element.attributes, function(attribute){
        return attribute.name === 'href' ? 'href' : attribute.name + '=' + attribute.value.slice(0, 60);
      });
      var style = getComputedStyle(element);
      linkDescriptors.push({
        attributes: attributes, display: style.display, isChip: isChip,
        tag: tagName(element), textLength: (element.textContent || '').trim().length
      });
    }

    function externalLink(element) {
      var link = tagName(element) === 'A' ? element : element.querySelector('a');
      return link && isExternalLink(link) ? link : null;
    }

    // A source citation trails a sentence: it follows sentence-ending
    // punctuation, and nothing but whitespace and other citations
    // follows it in its block.
    function isTrailingCitation(element, siblings, index, precedingText) {
      if (!externalLink(element) || !/[.!?)\\]]\\s*$/.test(precedingText)) { return false; }
      for (var i = index + 1; i < siblings.length; i++) {
        var sibling = siblings[i];
        if (sibling.nodeType === 3) { if (sibling.nodeValue.trim()) { return false; } continue; }
        if (sibling.nodeType !== 1 || isSkipped(sibling) || !(sibling.textContent || '').trim()) { continue; }
        if (!externalLink(sibling)) { return false; }
      }
      return true;
    }

    // A source citation chip: a short external link styled as a
    // citation, an element marked as a citation, or a "+N" sources
    // badge.
    function isCitationChip(element) {
      var text = (element.textContent || '').trim();
      if (/^\\+\\d+$/.test(text)) { return true; }
      for (var i = 0; i < element.attributes.length; i++) {
        var attribute = element.attributes[i];
        if (/citation|cite/i.test(attribute.name)) { return true; }
        if (/^(aria-label|class|data-testid|id)$/.test(attribute.name) && /citation|cite/i.test(attribute.value)) { return true; }
      }
      var link = tagName(element) === 'A' ? element : null;
      if (!link) { return false; }
      var isChip = isExternalLink(link) && text.length <= 80 && isCitationStyled(link);
      describe(link, isChip);
      return isChip;
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
        if (child.nodeType === 1 && isTrailingCitation(child, element.childNodes, i, inline)) {
          describe(externalLink(child), true);
          continue;
        }
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
    var text = isComplete && root ? blocks(root).join('\\n\\n') : '';
    return JSON.stringify({
      isComplete: isComplete,
      linkDescriptors: linkDescriptors,
      messageID: message ? (message.id || null) : null,
      text: text
    });
    """

    static let transcriptProbe = """
    // Takes an `anchorMessageID` argument, which may be empty.
    function lastMessageID(role) {
      var messages = document.querySelectorAll('[data-message-role="' + role + '"]');
      return messages.length ? (messages[messages.length - 1].id || null) : null;
    }

    var composer = document.querySelector('#mobile-composer-prompt')
                || document.querySelector('textarea[name="prompt"]')
                || document.querySelector('div[contenteditable="true"]')
                || document.querySelector('textarea');
    var composerText = composer ? (typeof composer.value === 'string' ? composer.value : composer.innerText) : '';
    var anchor = anchorMessageID ? document.getElementById(anchorMessageID) : null;
    return JSON.stringify({
      composerText: composerText || '',
      isAnchorPresent: !!anchor && anchor.getAttribute('data-message-role') === 'assistant',
      lastAssistantMessageID: lastMessageID('assistant'),
      lastUserMessageID: lastMessageID('user')
    });
    """
}
