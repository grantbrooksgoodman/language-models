// `fallbackMarkdown` escapes text as a CommonMark serializer does:
// ASCII punctuation is backslash-escaped, and some characters are
// written as character references. Code spans and fenced code
// blocks are written verbatim.
var characterReferences = { amp: '&', apos: "'", gt: '>', lt: '<', nbsp: String.fromCharCode(160), quot: '"' };

function isASCIIPunctuation(character) {
  var code = character.charCodeAt(0);
  return (code >= 33 && code <= 47) || (code >= 58 && code <= 64) || (code >= 91 && code <= 96) || (code >= 123 && code <= 126);
}

function decodeCharacterReference(name) {
  if (name.charAt(0) !== '#') {
    return Object.prototype.hasOwnProperty.call(characterReferences, name) ? characterReferences[name] : null;
  }
  var isHexadecimal = name.charAt(1) === 'x' || name.charAt(1) === 'X';
  var codePoint = parseInt(name.slice(isHexadecimal ? 2 : 1), isHexadecimal ? 16 : 10);
  if (codePoint === 0 || codePoint > 1114111 || (codePoint >= 55296 && codePoint <= 57343)) { codePoint = 65533; }
  return String.fromCodePoint(codePoint);
}

function closingBacktickRun(line, start, length) {
  var index = line.indexOf('`', start);
  while (index !== -1) {
    var runEnd = index;
    while (runEnd < line.length && line.charAt(runEnd) === '`') { runEnd++; }
    if (runEnd - index === length) { return index; }
    index = line.indexOf('`', runEnd);
  }
  return -1;
}

function unescapeInline(line) {
  var text = "";
  var index = 0;
  while (index < line.length) {
    var character = line.charAt(index);
    if (character === '\\' && index + 1 < line.length && isASCIIPunctuation(line.charAt(index + 1))) {
      text += line.charAt(index + 1);
      index += 2;
    } else if (character === '`') {
      var runEnd = index;
      while (runEnd < line.length && line.charAt(runEnd) === '`') { runEnd++; }
      var closingIndex = closingBacktickRun(line, runEnd, runEnd - index);
      var spanEnd = closingIndex === -1 ? runEnd : closingIndex + (runEnd - index);
      text += line.slice(index, spanEnd);
      index = spanEnd;
    } else if (character === '&') {
      var reference = /^&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});/.exec(line.slice(index));
      var decoded = reference ? decodeCharacterReference(reference[1]) : null;
      text += decoded === null ? character : decoded;
      index += decoded === null ? 1 : reference[0].length;
    } else {
      text += character;
      index++;
    }
  }
  return text;
}

function unescapeMarkdown(markdown) {
  var lines = markdown.split('\n');
  var openFence = null;
  for (var i = 0; i < lines.length; i++) {
    var fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(lines[i]);
    if (openFence) {
      if (fence && fence[1].charAt(0) === openFence.charAt(0) && fence[1].length >= openFence.length && fence[2].trim() === '') { openFence = null; }
    } else if (fence && !(fence[1].charAt(0) === '`' && fence[2].indexOf('`') !== -1)) {
      openFence = fence[1];
    } else {
      lines[i] = unescapeInline(lines[i]);
    }
  }
  return lines.join('\n');
}
