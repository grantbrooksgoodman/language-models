// Opens the fetch interceptor, which is injected at document start,
// for the main frame only. Defines the bridge that keeps recent POST
// responses and the shape of the last stream for `diagnosticsProbe`,
// and `post`, which sends a message to native. The interceptor's
// fragments follow, in the order `manifest.json` lists, and
// `fetchInterceptor.js` closes it.
(function(){
  if (window.__chatGPTBridge) { return; }
  var bridge = window.__chatGPTBridge = { generation: null, lastStream: null, recentResponses: [] };

  function post(message) {
    try {
      window.webkit.messageHandlers.{{bridgeMessageHandlerName}}.postMessage(JSON.stringify(message));
    } catch {}
  }
