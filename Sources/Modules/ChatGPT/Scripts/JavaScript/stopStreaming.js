// Stops the turn in flight by clicking the stop button, or the
// send button of a form that is still submitting, which acts as
// one. Does nothing when neither is present.
var stopButton = document.querySelector('[data-testid="stop-button"]');
if (stopButton) { stopButton.click(); return JSON.stringify({ ok: true, method: 'stop-button' }); }
var submittingForm = document.querySelector('form[data-octane-followup-submitting]');
var submitButton = submittingForm ? submittingForm.querySelector('button[data-composer-submit]') : null;
if (submitButton) { submitButton.click(); return JSON.stringify({ ok: true, method: 'submit-button' }); }
return JSON.stringify({ ok: true, method: 'none' });
