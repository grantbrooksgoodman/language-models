// Dismisses the login/safety gate sheet, if present.
var panel = document.querySelector('[data-conversation-gate-panel]');
if (!panel) { return JSON.stringify({ ok: true, reason: 'no gate' }); }
var closeButton = panel.querySelector('button[aria-label*="Close" i], button[aria-label*="Dismiss" i]');
if (closeButton) { closeButton.click(); return JSON.stringify({ ok: true, method: 'close-button' }); }
document.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
return JSON.stringify({ ok: true, method: 'escape' });
