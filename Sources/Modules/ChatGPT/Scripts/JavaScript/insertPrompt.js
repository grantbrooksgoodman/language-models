// Inserts `text` (a `callAsyncJavaScript` argument) into the composer.
// Tries a value setter for textareas and Selection/execCommand for a
// contenteditable, with a synthetic paste as a fallback. The text is
// reinserted until the send button accepts it, or the wait elapses.
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
