// Execute ScrcpyPane's profile methods against a fake settings store, so the
// confirm-before-overwrite and confirm-before-remove rules run without a shell.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const Model = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Model.js`, 'utf8'), Model);
const paneSource = readFileSync(`${__dirname}/../ScrcpyPane.qml`, 'utf8');

/** Pane state with QML's derived properties as getters. Example: paneFixture().saveProfile('Desk'). */
function paneFixture() {
  const sandbox = {
    Model,
    saved: { profilesJson: '[]', lastProfile: 'Balanced' },
    nameField: { text: '' },
    confirmExpiry: { restarts: 0, restart() { this.restarts++; } },
    profile: Model.builtInProfiles()[0],
    profileName: 'Balanced',
    baseProfileName: 'Balanced',
    message: '',
    failed: false,
    confirmOverwrite: '',
    confirmRemove: false
  };
  Object.defineProperty(sandbox, 'customProfiles', { get: () => Model.savedProfiles(sandbox.saved.profilesJson) });
  Object.defineProperty(sandbox, 'profiles', { get: () => Model.builtInProfiles().concat(sandbox.customProfiles) });
  const context = vm.createContext(sandbox);
  for (const declaration of paneSource.match(/^  function [\s\S]*?^  }/gm))
    vm.runInContext(declaration, context);
  return context;
}

const savedNames = pane => pane.customProfiles.map(p => p.name).join(',');

test('saving over an existing custom profile needs a second Save', () => {
  const pane = paneFixture();
  pane.saveProfile('Desk');
  assert.equal(savedNames(pane), 'Desk');
  pane.changeOption('fps', '30');
  pane.saveProfile('Desk');
  assert.equal(pane.confirmOverwrite, 'Desk');
  assert.match(pane.message, /already exists/);
  assert.notEqual(pane.customProfiles[0].fps, '30', 'first Save must not overwrite');
  pane.saveProfile('Desk');
  assert.equal(pane.confirmOverwrite, '');
  assert.equal(pane.customProfiles[0].fps, '30');
  assert.equal(savedNames(pane), 'Desk');
});

test('remove asks for confirmation, and an expired confirmation clears its prompt', () => {
  const pane = paneFixture();
  pane.saveProfile('Desk');
  pane.removeProfile();
  assert.equal(pane.confirmRemove, true);
  assert.equal(savedNames(pane), 'Desk', 'first Remove must not delete');
  assert.ok(pane.confirmExpiry.restarts > 0);
  pane.cancelConfirmations();
  assert.equal(pane.confirmRemove, false);
  assert.equal(pane.message, '');
  pane.removeProfile();
  pane.removeProfile();
  assert.equal(savedNames(pane), '');
  assert.equal(pane.profileName, 'Balanced');
  assert.match(pane.message, /Removed profile “Desk”/);
});
