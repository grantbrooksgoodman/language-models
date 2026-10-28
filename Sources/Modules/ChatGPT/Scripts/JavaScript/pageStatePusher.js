// Posts the page state whenever it changes: the document is observed
// for mutations, and the state is recomputed at most once per push
// interval, and after navigation events, which need not change the
// DOM.
var pushIntervalMilliseconds = {{pageStatePushIntervalMilliseconds}};
var lastPostedState = null;
var pushTimer = null;

function pushPageState() {
  pushTimer = null;
  var serialized;
  try { serialized = JSON.stringify(computePageState()); } catch { return; }
  if (serialized === lastPostedState) { return; }
  lastPostedState = serialized;
  post({ state: JSON.parse(serialized), type: 'pageState' });
}

function schedulePush() {
  if (pushTimer === null) { pushTimer = setTimeout(pushPageState, pushIntervalMilliseconds); }
}

function installPageStateObserver() {
  if (!document.documentElement) { return false; }
  new MutationObserver(schedulePush).observe(document.documentElement, { attributes: true, childList: true, subtree: true });
  schedulePush();
  return true;
}

if (!installPageStateObserver()) { document.addEventListener('DOMContentLoaded', installPageStateObserver); }
['load', 'pageshow', 'popstate'].forEach(function(name){ window.addEventListener(name, schedulePush); });
['pushState', 'replaceState'].forEach(function(name){
  var original = history[name];
  if (typeof original !== 'function') { return; }
  history[name] = function(){ var result = original.apply(this, arguments); schedulePush(); return result; };
});
