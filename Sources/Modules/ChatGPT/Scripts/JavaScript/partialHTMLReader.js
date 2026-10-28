// Reads the second mobile-web stream format:
// `text/vnd.openai.web-mobile-partial+html` – a sequence of
// `<template>` frames. The reply text lives in
// `<p data-assistant-stream-block-index="N">` blocks; completion
// arrives as a `data-conversation-control` island.
function decodeEntities(string) {
  return string.split('&quot;').join('"').split('&#39;').join("'").split('&lt;').join('<').split('&gt;').join('>').split('&amp;').join('&');
}

function stripTags(html) {
  var text = "";
  var depth = 0;
  for (var i = 0; i < html.length; i++) {
    var character = html.charAt(i);
    if (character === '<') { depth++; }
    else if (character === '>') { if (depth > 0) { depth--; } }
    else if (depth === 0) { text += character; }
  }
  return decodeEntities(text);
}

function joinByIndex(blocksByIndex) {
  var indices = Object.keys(blocksByIndex).map(Number).sort(function(first, second){ return first - second; });
  var segments = [];
  for (var i = 0; i < indices.length; i++) { segments.push(stripTags(blocksByIndex[indices[i]]).trim()); }
  return segments.join('\n\n');
}

// Committed blocks carry the finalized content of each paragraph,
// whatever its tag (so code blocks and other formatting are included):
// <?start name="…-committed-block-N">CONTENT<?end>.
function extractCommitted(html) {
  var committedBlockLabel = 'committed-block-';
  var pieces = html.split('<?start name="');
  var contentByIndex = {};
  var found = false;
  for (var i = 1; i < pieces.length; i++) {
    var piece = pieces[i];
    var nameEnd = piece.indexOf('"');
    if (nameEnd < 0) { continue; }
    var labelIndex = piece.indexOf(committedBlockLabel);
    if (labelIndex < 0 || labelIndex > nameEnd) { continue; }
    var tagEnd = piece.indexOf('>', nameEnd);
    if (tagEnd < 0) { continue; }
    var contentEnd = piece.indexOf('<?end>', tagEnd);
    if (contentEnd < 0) { continue; }
    contentByIndex[piece.slice(labelIndex + committedBlockLabel.length, nameEnd)] = piece.slice(tagEnd + 1, contentEnd);
    found = true;
  }
  return found ? joinByIndex(contentByIndex) : "";
}

// Pending blocks cover only `<p>` content; used as a fallback when
// no committed blocks are present.
function extractPending(html) {
  var pieces = html.split('data-assistant-stream-block-index="');
  var contentByIndex = {};
  for (var i = 1; i < pieces.length; i++) {
    var piece = pieces[i];
    var quoteEnd = piece.indexOf('"');
    if (quoteEnd < 0) { continue; }
    var tagEnd = piece.indexOf('>', quoteEnd);
    if (tagEnd < 0) { continue; }
    var contentEnd = piece.indexOf('</p>', tagEnd);
    if (contentEnd < 0) { continue; }
    contentByIndex[piece.slice(0, quoteEnd)] = piece.slice(tagEnd + 1, contentEnd);
  }
  return joinByIndex(contentByIndex);
}

function extractAssistantText(html) {
  return extractCommitted(html) || extractPending(html);
}

function readPartialHTML(stream, contentType, generation) {
  var reader = stream.getReader();
  var decoder = new TextDecoder();
  var buffer = "";
  var completed = false;
  var shape = bridge.lastStream = { contentType: contentType, length: 0, startDate: Date.now(), textSource: null };

  function finish() {
    if (completed) { return; }
    completed = true;
    var text = extractAssistantText(buffer);
    shape.length = buffer.length;
    shape.textSource = text ? 'partialHTML' : 'none';
    post({
      citationLabels: [], fullText: text, generation: generation, isFullTextIncomplete: false, messageID: null, textSource: shape.textSource, type: 'completed'
    });
  }

  function pump() {
    reader.read().then(function(result){
      if (result.done) { return finish(); }
      buffer += decoder.decode(result.value, { stream: true });
      // The message ends at the completion marker, whatever follows it.
      var markerIndex = buffer.indexOf('data-conversation-control="message-stream-complete"');
      if (markerIndex !== -1) { buffer = buffer.slice(0, markerIndex); return finish(); }
      pump();
    }).catch(function(){});
  }
  pump();
}
