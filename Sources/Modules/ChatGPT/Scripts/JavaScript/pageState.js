// Defines `computePageState()`, the one source of the page state the
// on-demand probe returns and the bridge pushes.
function computePageState() {
  function select(selector) { return document.querySelector(selector); }
  function lastMessage(role) {
    var messages = document.querySelectorAll('[data-message-role="' + role + '"]');
    return messages.length ? messages[messages.length - 1] : null;
  }
  var pathComponents = location.pathname.split('/').filter(Boolean);
  var conversationID = (pathComponents.length >= 2 && (pathComponents[0] === 'c' || pathComponents[0] === 'uc')) ? pathComponents[1] : null;
  var hasChallenge = !!document.querySelector('iframe[src*="challenges.cloudflare.com"]')
                  || /just a moment/i.test(document.title || "");
  // The mobile-web composer marks its form while a turn is in flight
  // (its send button acts as a stop button), and the assistant
  // message while it streams.
  var isStreaming = !!(select('[data-testid="stop-button"]')
                  || select('form[data-octane-followup-submitting]')
                  || select('[data-message-role="assistant"][data-message-streaming]'));
  var lastAssistantMessage = lastMessage('assistant');
  var lastUserMessage = lastMessage('user');
  return {
    isChallengePresent: hasChallenge,
    isComposerPresent: !!(select('#mobile-composer-prompt') || select('textarea[name="prompt"]')),
    isLastAssistantMessageComplete: !!lastAssistantMessage && lastAssistantMessage.hasAttribute('data-message-complete'),
    isLoggedOutModalPresent: !!select('[data-conversation-gate-panel]'),
    isStreaming: isStreaming,
    lastAssistantMessageID: lastAssistantMessage ? (lastAssistantMessage.id || null) : null,
    lastUserMessageID: lastUserMessage ? (lastUserMessage.id || null) : null,
    urlConversationID: conversationID
  };
}
