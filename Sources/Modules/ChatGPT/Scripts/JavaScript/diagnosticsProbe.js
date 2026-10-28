// A `callAsyncJavaScript` function body that returns the bridge's
// diagnostics – the shape of the last stream and recent POST
// responses – as a JSON string.
var bridge = window.__chatGPTBridge;
if (!bridge) { return JSON.stringify({ isInstalled: false }); }

function sortedKeys(keys) { return keys ? Object.keys(keys).sort() : undefined; }

var stream = bridge.lastStream;
return JSON.stringify({
  isInstalled: true,
  lastStream: stream ? {
    ageSeconds: Math.round((Date.now() - stream.startDate) / 1000),
    contentKeys: sortedKeys(stream.contentKeys),
    contentType: stream.contentType,
    dilKeys: sortedKeys(stream.dilKeys),
    eventTypes: stream.eventTypes,
    length: stream.length,
    referenceKeys: sortedKeys(stream.referenceKeys),
    textSource: stream.textSource,
    versions: sortedKeys(stream.versions)
  } : null,
  recentResponses: bridge.recentResponses
});
