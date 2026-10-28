// Closes the fetch interceptor opened by `bridgePrelude.js`. Wraps
// `window.fetch`, and for any POST whose response is a mobile-web
// conversation stream, tees the body, posts to native when the stream
// starts, and posts the assistant reply once the stream completes.
  function streamReader(contentType) {
    if (contentType.indexOf('openai.conversation-source') !== -1) { return readConversationSource; }
    if (contentType.indexOf('openai.web-mobile-partial') !== -1) { return readPartialHTML; }
    return null;
  }

  function recordResponse(input, response, contentType, isConversationStream) {
    if (response.status === 204) { return; }
    var url = ((input && input.url) || input) + '';
    bridge.recentResponses.push({
      contentType: contentType, isConversationStream: isConversationStream, path: url.split('?')[0], status: response.status
    });
    if (bridge.recentResponses.length > 20) { bridge.recentResponses.shift(); }
  }

  var originalFetch = window.fetch;
  window.fetch = function(input, init) {
    var method = (((init && init.method) || (input && input.method) || 'GET') + '').toUpperCase();
    // The turn that is sending stamps the bridge before it submits, so
    // the stream is tagged with the turn that caused it.
    var generation = method === 'POST' && bridge.generation !== undefined ? bridge.generation : null;

    var promise = originalFetch.apply(this, arguments);
    if (method !== 'POST') { return promise; }

    return promise.then(function(response){
      try {
        var contentType = (response.headers && response.headers.get && response.headers.get('content-type')) || '';
        var readStream = streamReader(contentType);
        recordResponse(input, response, contentType, !!readStream);
        if (!readStream) { return response; }

        if (!response.body || !response.body.tee) { return response; }
        var teedStreams = response.body.tee();
        post({ generation: generation, type: 'started' });
        readStream(teedStreams[1], contentType, generation);
        return new Response(teedStreams[0], response);
      } catch { return response; }
    });
  };
})();
