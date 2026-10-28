// Composes the injected scripts exactly as the package's loader does:
// reads `manifest.json`, joins a composition's fragments with a blank
// line, and substitutes placeholders.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const scriptsDirectory = join(
  dirname(fileURLToPath(import.meta.url)), '..', 'Sources', 'Modules', 'ChatGPT', 'Scripts', 'JavaScript'
);

export const placeholderValues = { bridgeMessageHandlerName: 'chatGPTBridge', pageStatePushIntervalMilliseconds: 100 };

export function loadManifest() {
  return JSON.parse(readFileSync(join(scriptsDirectory, 'manifest.json'), 'utf8'));
}

function loadFile(manifest, name) {
  var source = readFileSync(join(scriptsDirectory, name + '.js'), 'utf8');
  for (var placeholder of manifest.placeholders) {
    source = source.split('{{' + placeholder + '}}').join(placeholderValues[placeholder]);
  }
  return source;
}

export function composeScript(manifest, name) {
  var fragments = manifest.compositions[name];
  if (!fragments) { return loadFile(manifest, name); }
  return fragments.map(function (fragment) { return loadFile(manifest, fragment); }).join('\n\n');
}

export function scriptNames(manifest) {
  return Object.keys(manifest.scripts).sort();
}
