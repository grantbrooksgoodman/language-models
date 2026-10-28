// Submits the composer by clicking its send button
// (`[data-composer-submit]`), or submitting the enclosing form if no
// button is found. Takes a `generation` argument, the sending turn's
// number, which stamps the bridge immediately before sending so the
// stream the send causes is tagged with it.
var composer = document.querySelector('#mobile-composer-prompt')
      || document.querySelector('textarea[name="prompt"]');
if (!composer) { return JSON.stringify({ ok: false, reason: 'no composer for send' }); }
composer.focus();

var sendButton = document.querySelector('button[data-composer-submit]')
       || document.querySelector('button[aria-label="Send message" i]');
var bridge = window.__chatGPTBridge;
var bridgeInstalled = !!bridge;
function stamp() { if (bridge) { bridge.generation = generation; } }
if (!sendButton) {
  var form = composer.form || (composer.closest && composer.closest('form'));
  if (form && form.requestSubmit) {
    stamp();
    form.requestSubmit();
    return JSON.stringify({ ok: true, method: 'requestSubmit', bridgeInstalled: bridgeInstalled });
  }
  return JSON.stringify({ ok: false, reason: 'no send button' });
}
if (sendButton.disabled || sendButton.getAttribute('aria-disabled') === 'true') {
  return JSON.stringify({ ok: false, reason: 'send button disabled', readyState: document.readyState });
}
stamp();
sendButton.click();
return JSON.stringify({ ok: true, method: 'click', bridgeInstalled: bridgeInstalled });
