// The logged-out web view – which presents a desktop Safari user agent
// at a phone-width viewport – is served the mobile-web (`unauth-mweb`)
// experience, whose conversation response streams in one of two
// formats. This reads the first:
// `application/vnd.openai.conversation-source+ndjson` –
// newline-delimited JSON events; an `end` event closes the stream.
// Each `content` event carries its message's text in `markdown`, which
// replaces or appends to the message according to the event's `mode`,
// and in `dil.fallbackMarkdown`, a rendering of the whole message so
// far whose text is escaped as in CommonMark. The reply is read from
// `markdown` when it is non-empty, and otherwise from the unescaped
// rendering.
// Reads the NDJSON conversation-source stream. A `content` event
// replaces its message's markdown, or appends to it when its
// `mode` is `append`, and carries a `fallbackMarkdown` rendering
// of the whole message so far, and the `references` its sources
// cite. The reply is the latest message to change: its markdown
// if non-empty, else its unescaped rendering, which omits the
// content of any components the message requires and renders a
// source citation as its label. The labels of the message's
// references are posted with the reply so they can be stripped.
function readConversationSource(stream, contentType, generation) {
  var reader = stream.getReader();
  var decoder = new TextDecoder();
  var buffer = "";
  var completed = false;
  var citationLabelsByMessageID = {};
  var fallbackMarkdownByMessageID = {};
  var hasLinksByMessageID = {};
  var latestMessageID = null;
  var markdownByMessageID = {};
  var requiredComponentsByMessageID = {};
  var shape = bridge.lastStream = {
    contentKeys: {}, contentType: contentType, dilKeys: {}, eventTypes: {}, referenceKeys: {}, startDate: Date.now(), textSource: null, versions: {}
  };

  function recordKeys(keys, object) {
    if (object && typeof object === 'object') { Object.keys(object).forEach(function(key){ keys[key] = true; }); }
  }

  // Collects the labels a citation may be rendered with: the host
  // of every URL, with and without `www.`, and the strings under
  // keys that name a display label.
  var labelKeys = ['attribution', 'label', 'name', 'title'];
  function collectLabels(value, labels, depth, key) {
    if (depth > 6 || value === null || value === undefined) { return; }
    if (typeof value === 'string') {
      var text = value.trim();
      if (!text || text.length > 120) { return; }
      if (/^https?:/i.test(text)) {
        try { var host = new URL(text).hostname; labels[host] = true; labels[host.replace(/^www\./, '')] = true; } catch {}
        return;
      }
      if (labelKeys.indexOf(key) !== -1) { labels[text] = true; }
    } else if (Array.isArray(value)) {
      value.forEach(function(element){ collectLabels(element, labels, depth + 1, key); });
    } else if (typeof value === 'object') {
      recordKeys(shape.referenceKeys, value);
      Object.keys(value).forEach(function(childKey){ collectLabels(value[childKey], labels, depth + 1, childKey); });
    }
  }

  function finish() {
    if (completed) { return; }
    completed = true;
    var markdown = latestMessageID === null ? "" : (markdownByMessageID[latestMessageID] || "").trim();
    var fallbackMarkdown = latestMessageID === null ? "" : unescapeMarkdown(fallbackMarkdownByMessageID[latestMessageID] || "").trim();
    var requiredComponents = (latestMessageID !== null && requiredComponentsByMessageID[latestMessageID]) || [];
    var citationLabels = Object.keys((latestMessageID !== null && citationLabelsByMessageID[latestMessageID]) || {});
    var hasLinks = latestMessageID !== null && !!hasLinksByMessageID[latestMessageID];
    shape.textSource = markdown ? 'markdown' : (fallbackMarkdown ? 'fallbackMarkdown' : 'none');
    // A rendering with links is read from the page, which marks
    // its citations; the rendering shows them as plain labels.
    post({
      citationLabels: citationLabels,
      fullText: markdown || fallbackMarkdown,
      generation: generation,
      isFullTextIncomplete: !markdown && (requiredComponents.length > 0 || citationLabels.length > 0 || hasLinks),
      messageID: latestMessageID,
      textSource: shape.textSource,
      type: 'completed'
    });
  }

  function handleLine(line) {
    var event;
    try { event = JSON.parse(line); } catch { return; }
    if (!event || typeof event !== 'object') { return; }
    shape.eventTypes[event.type] = (shape.eventTypes[event.type] || 0) + 1;
    if (event.version !== undefined) { shape.versions[event.version] = true; }
    if (event.type === 'end') { return finish(); }
    if (event.type !== 'content' || typeof event.messageId !== 'string') { return; }

    recordKeys(shape.contentKeys, event);
    recordKeys(shape.dilKeys, event.dil);
    var messageID = event.messageId;
    latestMessageID = messageID;
    if (typeof event.markdown === 'string') {
      var priorMarkdown = event.mode === 'append' ? (markdownByMessageID[messageID] || "") : "";
      markdownByMessageID[messageID] = priorMarkdown + event.markdown;
    }
    if (event.dil && typeof event.dil.fallbackMarkdown === 'string') {
      fallbackMarkdownByMessageID[messageID] = event.dil.fallbackMarkdown;
    }
    if (event.dil && Array.isArray(event.dil.requiredComponents)) {
      requiredComponentsByMessageID[messageID] = event.dil.requiredComponents;
    }
    if (event.dil && /https?:\/\//i.test(JSON.stringify(event.dil))) {
      hasLinksByMessageID[messageID] = true;
    }
    if (event.references !== undefined && event.references !== null) {
      var labels = citationLabelsByMessageID[messageID] || (citationLabelsByMessageID[messageID] = {});
      collectLabels(event.references, labels, 0, null);
    }
  }

  function pump() {
    reader.read().then(function(result){
      if (result.done) {
        handleLine(buffer + decoder.decode());
        return finish();
      }
      buffer += decoder.decode(result.value, { stream: true });
      var lines = buffer.split('\n');
      buffer = lines.pop();
      for (var i = 0; i < lines.length && !completed; i++) { handleLine(lines[i]); }
      if (!completed) { pump(); }
    }).catch(function(){});
  }
  pump();
}
