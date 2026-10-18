// Loads a plugin .js file into its own vm context, the way QML does: each
// `.import "X.js" as X` line becomes a namespace X loaded the same way.
const { readFileSync } = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const repo = path.resolve(__dirname, '..');
const IMPORT_LINE = /^\.import "([^"]+\.js)" as (\w+)$/gm;

/** Example: loadJs('Webcam.js').webcamSettings('') — Webcam.js sees DeviceInfo. */
function loadJs(file) {
  const source = readFileSync(path.join(repo, file), 'utf8');
  const context = vm.createContext({});
  for (const [, imported, name] of source.matchAll(IMPORT_LINE))
    context[name] = loadJs(imported);
  vm.runInContext(source.replace(IMPORT_LINE, ''), context);
  return context;
}

module.exports = { loadJs };
