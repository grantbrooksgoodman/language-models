# ScriptHarness

A developer tool for the JavaScript that LanguageModels injects into the ChatGPT web view. It lives outside every Swift package target and has no dependencies beyond Node.js built-ins.

## Requirements

Node.js 18 or later.

## Check Syntax

```sh
node ScriptHarness/check.mjs
```

`check.mjs` composes every script exactly as the package's loader does – reading `Sources/Modules/ChatGPT/Scripts/JavaScript/manifest.json`, joining a composition's fragments, and substituting placeholders – then compiles each one in its execution context without running it. Document-start scripts compile as classic scripts; `callAsyncJavaScript` function bodies compile as async function bodies that take the argument names the manifest lists for them. The command prints one line per script and exits with a non-zero status, naming the script, on any syntax error.

Pass `--emit <directory>` to also write each composed script to that directory, for comparison with another build of the scripts.

## Replay Recorded Streams

```sh
node ScriptHarness/replay.mjs
```

`replay.mjs` composes the fetch interceptor exactly as `check.mjs` does, installs it over a stub `window.fetch` that serves a fixture's body, and calls the wrapped `fetch` as the page would. It confirms that the page receives the body byte for byte, waits for the bridge to post its completion, and compares every posted message with the fixture's `expected.json`. Each fixture is replayed five ways – the whole body in one chunk, fixed chunks of 1, 7, and 64 bytes, and chunks cut inside every multi-byte UTF-8 sequence – and every way must produce identical messages. The command also runs the `unescapeMarkdown` cases in `UnescaperCases.json`. It exits with a non-zero status on any failure.

### Add a Fixture

Create `ScriptHarness/Fixtures/<name>/` with three files:

| File | Contents |
| --- | --- |
| `body.txt` | The raw response body, exactly as served. |
| `meta.json` | `contentType` and `url`, the response's `Content-Type` and the request URL. |
| `expected.json` | The messages the bridge posts for the body, in order. |

Use harmless prompts with no personal data when recording a body, because fixtures live in the repository.

### Update Expected Output

```sh
node ScriptHarness/replay.mjs --update
```

`--update` rewrites every fixture's `expected.json` from the current output. Use it to record a new fixture, or after a deliberate change to the bridge, and review the resulting diff.
