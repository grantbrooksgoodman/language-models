// Replays recorded conversation streams through the composed fetch
// interceptor and compares the messages it posts with each fixture's
// expected output. Usage: node ScriptHarness/replay.mjs [--update]
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { composeScript, loadManifest, placeholderValues } from './compose.mjs';

const harnessDirectory = dirname(fileURLToPath(import.meta.url));
const fixturesDirectory = join(harnessDirectory, 'Fixtures');
const isUpdating = process.argv.includes('--update');
const manifest = loadManifest();
const interceptorSource = composeScript(manifest, 'fetchInterceptor');
const unescaperSource = composeScript(manifest, 'unescaper');

// Chunkings: the whole body, fixed sizes, and cuts inside every
// multi-byte UTF-8 sequence.
function chunkings(bytes) {
  function fixed(size) {
    var chunks = [];
    for (var offset = 0; offset < bytes.length; offset += size) { chunks.push(bytes.subarray(offset, offset + size)); }
    return chunks;
  }
  function insideMultibyte() {
    var chunks = [];
    var start = 0;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] >= 0xC0) { chunks.push(bytes.subarray(start, index + 1)); start = index + 1; }
    }
    chunks.push(bytes.subarray(start));
    return chunks.filter(function (chunk) { return chunk.length > 0; });
  }
  return {
    whole: [bytes], bytes1: fixed(1), bytes7: fixed(7), bytes64: fixed(64), insideMultibyte: insideMultibyte()
  };
}

function streamOf(chunks) {
  var index = 0;
  return new ReadableStream({
    pull(controller) {
      if (index < chunks.length) { controller.enqueue(chunks[index++]); } else { controller.close(); }
    }
  });
}

async function readAll(stream) {
  var reader = stream.getReader();
  var parts = [];
  while (true) {
    var result = await reader.read();
    if (result.done) { break; }
    parts.push(result.value);
  }
  return Buffer.concat(parts);
}

function waitFor(condition, timeoutMilliseconds) {
  return new Promise(function (resolve) {
    var deadline = Date.now() + timeoutMilliseconds;
    (function check() {
      if (condition() || Date.now() >= deadline) { return resolve(); }
      setTimeout(check, 5);
    })();
  });
}

// Installs the interceptor over a stub `window.fetch` that serves the
// fixture body, with the stubs the interceptor reads when it installs.
function installInterceptor(fetch, messages) {
  var window = {
    addEventListener() {},
    document: { addEventListener() {}, documentElement: null, querySelector() { return null; }, querySelectorAll() { return []; } },
    history: { pushState() {}, replaceState() {} },
    location: { pathname: '/', href: 'https://chatgpt.com/' }
  };
  window.webkit = { messageHandlers: {} };
  window.webkit.messageHandlers[placeholderValues.bridgeMessageHandlerName] = {
    postMessage(json) { messages.push(JSON.parse(json)); }
  };
  window.fetch = fetch;
  new Function('window', 'document', 'location', 'history', interceptorSource)(window, window.document, window.location, window.history);
  return window;
}

function fixtureFetch(bodyChunks, contentType) {
  return function () {
    return Promise.resolve(new Response(streamOf(bodyChunks), { headers: { 'content-type': contentType } }));
  };
}

async function replay(fixture, chunking, chunks) {
  var messages = [];
  var window = installInterceptor(fixtureFetch(chunks, fixture.meta.contentType), messages);
  var response = await window.fetch(fixture.meta.url, { method: 'POST' });
  var pageBranch = await readAll(response.body);
  if (!pageBranch.equals(fixture.bytes)) { throw new Error(chunking + ': the page received a different body'); }
  await waitFor(function () { return messages.some(function (m) { return m.type === 'completed'; }); }, 2000);
  return messages;
}

function loadFixture(name) {
  var directory = join(fixturesDirectory, name);
  var bytes = readFileSync(join(directory, 'body.txt'));
  var meta = JSON.parse(readFileSync(join(directory, 'meta.json'), 'utf8'));
  var expectedPath = join(directory, 'expected.json');
  var expected = null;
  try { expected = JSON.parse(readFileSync(expectedPath, 'utf8')); } catch {}
  return { name: name, bytes: bytes, meta: meta, expected: expected, expectedPath: expectedPath };
}

function same(first, second) { return JSON.stringify(first) === JSON.stringify(second); }

async function replayFixture(fixture) {
  var results = {};
  for (var [chunking, chunks] of Object.entries(chunkings(fixture.bytes))) {
    results[chunking] = await replay(fixture, chunking, chunks);
  }
  var reference = results.whole;
  var failures = [];
  for (var [chunking, messages] of Object.entries(results)) {
    if (!same(messages, reference)) { failures.push(chunking + ' differs from whole'); }
  }
  if (isUpdating) {
    writeFileSync(fixture.expectedPath, JSON.stringify(reference, null, 2) + '\n');
  } else if (!same(reference, fixture.expected)) {
    failures.push('messages differ from expected.json');
  }
  return { chunkings: Object.keys(results), failures: failures };
}

function checkUnescaper() {
  var unescapeMarkdown = new Function(unescaperSource + '\nreturn unescapeMarkdown;')();
  var cases = JSON.parse(readFileSync(join(harnessDirectory, 'UnescaperCases.json'), 'utf8'));
  var failures = [];
  for (var item of cases) {
    var actual = unescapeMarkdown(item.input);
    if (actual !== item.output) { failures.push(JSON.stringify(item.input) + ' -> ' + JSON.stringify(actual) + ', expected ' + JSON.stringify(item.output)); }
  }
  return { count: cases.length, failures: failures };
}

var totalFailures = 0;
for (var name of readdirSync(fixturesDirectory).sort()) {
  var fixture = loadFixture(name);
  try {
    var result = await replayFixture(fixture);
    totalFailures += result.failures.length;
    console.log((result.failures.length ? 'FAIL  ' : 'ok    ') + name + ' [' + result.chunkings.join(', ') + ']'
      + (result.failures.length ? '\n      ' + result.failures.join('\n      ') : ''));
  } catch (error) {
    totalFailures += 1;
    console.log('FAIL  ' + name + ': ' + error.message);
  }
}

// Two overlapping requests: A is sent under generation 1 and finishes
// only after B, sent under generation 2, has started.
async function checkOverlap() {
  var messages = [];
  var controllers = [];
  var window = installInterceptor(function () {
    var stream = new ReadableStream({ start(controller) { controllers.push(controller); } });
    return Promise.resolve(new Response(stream, { headers: { 'content-type': 'application/vnd.openai.conversation-source+ndjson' } }));
  }, messages);
  var encoder = new TextEncoder();
  window.__chatGPTBridge.generation = 1;
  var responseA = await window.fetch('https://chatgpt.com/a', { method: 'POST' });
  window.__chatGPTBridge.generation = 2;
  var responseB = await window.fetch('https://chatgpt.com/b', { method: 'POST' });
  controllers[1].enqueue(encoder.encode('{"type":"content","messageId":"b","markdown":"B"}\n{"type":"end"}\n'));
  controllers[1].close();
  await waitFor(function () { return messages.filter(function (m) { return m.type === 'completed'; }).length === 1; }, 2000);
  controllers[0].enqueue(encoder.encode('{"type":"content","messageId":"a","markdown":"A"}\n{"type":"end"}\n'));
  controllers[0].close();
  await waitFor(function () { return messages.filter(function (m) { return m.type === 'completed'; }).length === 2; }, 2000);
  await readAll(responseA.body);
  await readAll(responseB.body);
  var summary = messages.map(function (m) { return m.type + ':' + (m.messageID || '-') + ':' + m.generation; });
  var expected = ['started:-:1', 'started:-:2', 'completed:b:2', 'completed:a:1'];
  return { summary: summary, failures: same(summary, expected) ? [] : ['got ' + summary.join(' ') + ', expected ' + expected.join(' ')] };
}

var overlap = await checkOverlap();
totalFailures += overlap.failures.length;
console.log((overlap.failures.length ? 'FAIL  ' : 'ok    ') + 'overlap [' + overlap.summary.join(', ') + ']'
  + (overlap.failures.length ? '\n      ' + overlap.failures.join('\n      ') : ''));

var unescaper = checkUnescaper();
totalFailures += unescaper.failures.length;
console.log((unescaper.failures.length ? 'FAIL  ' : 'ok    ') + 'unescaper (' + unescaper.count + ' cases)'
  + (unescaper.failures.length ? '\n      ' + unescaper.failures.join('\n      ') : ''));
console.log(totalFailures ? totalFailures + ' failure(s)' : 'all replays pass' + (isUpdating ? ' (expected.json files rewritten)' : ''));
process.exit(totalFailures ? 1 : 0);
