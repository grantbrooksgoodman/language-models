// Starts a new chat via a control if one exists, else navigates to `/`.
// A control that leaves the page on its conversation is followed by
// the navigation.
function isOnConversation() { return /^\/u?c\//.test(location.pathname); }
var newChatButton = document.querySelector('[data-testid="new-chat-button"]')
       || document.querySelector('button[aria-label*="New chat" i]')
       || document.querySelector('a[aria-label*="New chat" i]');
if (newChatButton) {
  newChatButton.click();
  await new Promise(function(resolve){ setTimeout(resolve, 500); });
  if (!isOnConversation()) { return JSON.stringify({ ok: true, method: 'button' }); }
}
location.assign('/');
return JSON.stringify({ ok: true, method: 'nav' });
