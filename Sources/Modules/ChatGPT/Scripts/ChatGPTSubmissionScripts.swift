//
//  ChatGPTSubmissionScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Injected-on-demand scripts that drive the page: inserting a prompt
/// into the composer, submitting it (by clicking the send button),
/// dismissing the login/safety sheet, and starting a new chat. Each
/// script returns a JSON status, with diagnostics when it can't find its
/// target.
enum ChatGPTSubmissionScripts {
    /// Submits the composer by clicking its send button
    /// (`[data-composer-submit]`), or submitting the enclosing form if no
    /// button is found.
    static let sendPrompt = """
    var composer = document.querySelector('#mobile-composer-prompt')
          || document.querySelector('textarea[name="prompt"]');
    if (!composer) { return JSON.stringify({ ok: false, reason: 'no composer for send' }); }
    composer.focus();

    var sendButton = document.querySelector('button[data-composer-submit]')
           || document.querySelector('button[aria-label="Send message" i]');
    if (!sendButton) {
      var form = composer.form || (composer.closest && composer.closest('form'));
      if (form && form.requestSubmit) { form.requestSubmit(); return JSON.stringify({ ok: true, method: 'requestSubmit' }); }
      return JSON.stringify({ ok: false, reason: 'no send button' });
    }
    if (sendButton.disabled || sendButton.getAttribute('aria-disabled') === 'true') {
      return JSON.stringify({ ok: false, reason: 'send button disabled' });
    }
    sendButton.click();
    return JSON.stringify({ ok: true, method: 'click' });
    """

    /// Dismisses the login/safety gate sheet, if present.
    static let dismissGate = """
    var panel = document.querySelector('[data-conversation-gate-panel]');
    if (!panel) { return JSON.stringify({ ok: true, reason: 'no gate' }); }
    var closeButton = panel.querySelector('button[aria-label*="Close" i], button[aria-label*="Dismiss" i]');
    if (closeButton) { closeButton.click(); return JSON.stringify({ ok: true, method: 'close-button' }); }
    document.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
    return JSON.stringify({ ok: true, method: 'escape' });
    """

    /// Inserts `text` (a callAsyncJavaScript argument) into the composer.
    /// Tries a value setter for textareas and Selection/execCommand for a
    /// contenteditable, with a synthetic paste as a fallback.
    static let insertPrompt = """
    function findComposer() {
      return document.querySelector('#mobile-composer-prompt')
          || document.querySelector('textarea[name="prompt"]')
          || document.querySelector('div[contenteditable="true"]')
          || document.querySelector('textarea');
    }
    var composer = findComposer();
    if (!composer) {
      var candidates = [];
      var elements = document.querySelectorAll('textarea, [contenteditable], input[type="text"]');
      for (var i = 0; i < elements.length && i < 6; i++) {
        candidates.push((elements[i].tagName || '') + '#' + (elements[i].id || '') + '.' + ((elements[i].className || '') + '').slice(0, 40));
      }
      return JSON.stringify({ ok: false, reason: 'no composer', candidates: candidates });
    }
    composer.focus();
    var tag = composer.tagName.toLowerCase();
    var isField = (tag === 'textarea' || tag === 'input');
    if (isField) {
      try {
        var prototype = tag === 'textarea' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(prototype, 'value').set.call(composer, text);
      } catch { composer.value = text; }
      composer.dispatchEvent(new Event('input', { bubbles: true }));
    } else {
      try {
        var selection = window.getSelection();
        var range = document.createRange();
        range.selectNodeContents(composer);
        selection.removeAllRanges();
        selection.addRange(range);
      } catch {}
      document.execCommand('insertText', false, text);
    }
    var current = isField ? composer.value : composer.innerText;
    if ((current || '').indexOf(text) === -1) {
      try {
        var dataTransfer = new DataTransfer();
        dataTransfer.setData('text/plain', text);
        composer.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dataTransfer }));
      } catch {}
      current = isField ? composer.value : composer.innerText;
    }
    return JSON.stringify({ ok: (current || '').indexOf(text) !== -1, tag: tag, id: composer.id || '', current: (current || '').slice(0, 100) });
    """

    /// Starts a new chat via a control if one exists, else navigates to `/`.
    static let startNewChat = """
    var newChatButton = document.querySelector('[data-testid="new-chat-button"]')
           || document.querySelector('button[aria-label*="New chat" i]')
           || document.querySelector('a[aria-label*="New chat" i]');
    if (newChatButton) { newChatButton.click(); return JSON.stringify({ ok: true, method: 'button' }); }
    location.assign('/');
    return JSON.stringify({ ok: true, method: 'nav' });
    """
}
