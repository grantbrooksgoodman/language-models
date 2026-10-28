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
