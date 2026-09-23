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
    var el = document.querySelector('#mobile-composer-prompt')
          || document.querySelector('textarea[name="prompt"]');
    if (!el) { return JSON.stringify({ ok: false, reason: 'no composer for send' }); }
    el.focus();

    var btn = document.querySelector('button[data-composer-submit]')
           || document.querySelector('button[aria-label="Send message" i]');
    if (!btn) {
      var form = el.form || (el.closest && el.closest('form'));
      if (form && form.requestSubmit) { form.requestSubmit(); return JSON.stringify({ ok: true, method: 'requestSubmit' }); }
      return JSON.stringify({ ok: false, reason: 'no send button' });
    }
    if (btn.disabled || btn.getAttribute('aria-disabled') === 'true') {
      return JSON.stringify({ ok: false, reason: 'send button disabled' });
    }
    btn.click();
    return JSON.stringify({ ok: true, method: 'click' });
    """

    /// Dismisses the login/safety gate sheet, if present.
    static let dismissGate = """
    var panel = document.querySelector('[data-conversation-gate-panel]');
    if (!panel) { return JSON.stringify({ ok: true, reason: 'no gate' }); }
    var closeBtn = panel.querySelector('button[aria-label*="Close" i], button[aria-label*="Dismiss" i]');
    if (closeBtn) { closeBtn.click(); return JSON.stringify({ ok: true, method: 'close-button' }); }
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
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
    var el = findComposer();
    if (!el) {
      var cands = [];
      var all = document.querySelectorAll('textarea, [contenteditable], input[type="text"]');
      for (var i = 0; i < all.length && i < 6; i++) {
        cands.push((all[i].tagName || '') + '#' + (all[i].id || '') + '.' + ((all[i].className || '') + '').slice(0, 40));
      }
      return JSON.stringify({ ok: false, reason: 'no composer', candidates: cands });
    }
    el.focus();
    var tag = el.tagName.toLowerCase();
    var isField = (tag === 'textarea' || tag === 'input');
    if (isField) {
      try {
        var proto = tag === 'textarea' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
      } catch (e) { el.value = text; }
      el.dispatchEvent(new Event('input', { bubbles: true }));
    } else {
      try {
        var sel = window.getSelection();
        var range = document.createRange();
        range.selectNodeContents(el);
        sel.removeAllRanges();
        sel.addRange(range);
      } catch (e) {}
      document.execCommand('insertText', false, text);
    }
    var current = isField ? el.value : el.innerText;
    if ((current || '').indexOf(text) === -1) {
      try {
        var dt = new DataTransfer();
        dt.setData('text/plain', text);
        el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
      } catch (e) {}
      current = isField ? el.value : el.innerText;
    }
    return JSON.stringify({ ok: (current || '').indexOf(text) !== -1, tag: tag, id: el.id || '', current: (current || '').slice(0, 100) });
    """

    /// Starts a new chat via a control if one exists, else navigates to `/`.
    static let startNewChat = """
    var btn = document.querySelector('[data-testid="new-chat-button"]')
           || document.querySelector('button[aria-label*="New chat" i]')
           || document.querySelector('a[aria-label*="New chat" i]');
    if (btn) { btn.click(); return JSON.stringify({ ok: true, method: 'button' }); }
    location.assign('/');
    return JSON.stringify({ ok: true, method: 'nav' });
    """
}
