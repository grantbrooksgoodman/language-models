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
/// dismissing the login/safety sheet, stopping the turn in flight, and
/// starting a new chat. Each script returns a JSON status, with
/// diagnostics when it can't find its target.
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
      return JSON.stringify({ ok: false, reason: 'send button disabled', readyState: document.readyState });
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
    /// contenteditable, with a synthetic paste as a fallback. The text is
    /// reinserted until the send button accepts it, or the wait elapses.
    static let insertPrompt = """
    function findComposer() {
      return document.querySelector('#mobile-composer-prompt')
          || document.querySelector('textarea[name="prompt"]')
          || document.querySelector('div[contenteditable="true"]')
          || document.querySelector('textarea');
    }
    function findSendButton() {
      return document.querySelector('button[data-composer-submit]')
          || document.querySelector('button[aria-label="Send message" i]');
    }
    function isDisabled(button) { return button.disabled || button.getAttribute('aria-disabled') === 'true'; }
    function currentText(composer) {
      var tag = composer.tagName.toLowerCase();
      return ((tag === 'textarea' || tag === 'input') ? composer.value : composer.innerText) || '';
    }
    function insert(composer) {
      var tag = composer.tagName.toLowerCase();
      if (tag === 'textarea' || tag === 'input') {
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
      if (currentText(composer).indexOf(text) === -1) {
        try {
          var dataTransfer = new DataTransfer();
          dataTransfer.setData('text/plain', text);
          composer.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dataTransfer }));
        } catch {}
      }
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
    insert(composer);
    // The page serves its composer before its send button accepts
    // input, so the text is reinserted until the button does.
    var deadline = Date.now() + 2000;
    var sendButton = findSendButton();
    while (sendButton && isDisabled(sendButton) && Date.now() < deadline) {
      await new Promise(function(resolve){ setTimeout(resolve, 100); });
      composer = findComposer() || composer;
      sendButton = findSendButton();
      if (sendButton && isDisabled(sendButton)) { insert(composer); }
    }
    var current = currentText(composer);
    var isAccepted = !sendButton || !isDisabled(sendButton);
    return JSON.stringify({
      ok: current.indexOf(text) !== -1 && isAccepted,
      reason: isAccepted ? undefined : 'send button disabled after insertion',
      tag: composer.tagName.toLowerCase(), id: composer.id || '', current: current.slice(0, 100), readyState: document.readyState
    });
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

    static let stopStreaming = """
    // Stops the turn in flight by clicking the stop button, or the
    // send button of a form that is still submitting, which acts as
    // one. Does nothing when neither is present.
    var stopButton = document.querySelector('[data-testid="stop-button"]');
    if (stopButton) { stopButton.click(); return JSON.stringify({ ok: true, method: 'stop-button' }); }
    var submittingForm = document.querySelector('form[data-octane-followup-submitting]');
    var submitButton = submittingForm ? submittingForm.querySelector('button[data-composer-submit]') : null;
    if (submitButton) { submitButton.click(); return JSON.stringify({ ok: true, method: 'submit-button' }); }
    return JSON.stringify({ ok: true, method: 'none' });
    """
}
