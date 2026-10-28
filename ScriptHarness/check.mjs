// Syntax-checks every injected script in its execution context without
// running it. Usage: node ScriptHarness/check.mjs [--emit <directory>]
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';
import { composeScript, loadManifest, scriptNames } from './compose.mjs';

const AsyncFunction = (async () => {}).constructor;

function check(manifest, name) {
  var source = composeScript(manifest, name);
  var script = manifest.scripts[name];
  if (script.kind === 'documentStart') {
    new vm.Script(source, { filename: name + '.js' });
  } else if (script.kind === 'functionBody') {
    new AsyncFunction(...(script.arguments || []), source);
  } else {
    throw new Error('unknown kind "' + script.kind + '"');
  }
  return source;
}

var manifest = loadManifest();
var emitIndex = process.argv.indexOf('--emit');
var emitDirectory = emitIndex === -1 ? null : process.argv[emitIndex + 1];
if (emitDirectory) { mkdirSync(emitDirectory, { recursive: true }); }

var failures = 0;
for (var name of scriptNames(manifest)) {
  try {
    var source = check(manifest, name);
    if (emitDirectory) { writeFileSync(join(emitDirectory, name + '.js'), source); }
    console.log('ok    ' + name);
  } catch (error) {
    failures += 1;
    console.error('error ' + name + ': ' + error.message);
  }
}

console.log(failures ? failures + ' script(s) failed' : 'all ' + scriptNames(manifest).length + ' scripts pass');
process.exit(failures ? 1 : 0);
