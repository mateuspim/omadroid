// DevicePower.js projections. tests/device-power.sh covers device-power.sh itself.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const power = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../DevicePower.js`, 'utf8'), power);
const plain = (value) => JSON.parse(JSON.stringify(value));

test('parsePowerStatus reads the status line', () => {
  assert.deepEqual(plain(power.parsePowerStatus('keep=on running=1 secret=saved\n')), { keepAwake: true, running: true, secret: 'saved' });
  assert.deepEqual(plain(power.parsePowerStatus('keep=off running=0 secret=blocked')), { keepAwake: false, running: false, secret: 'blocked' });
});

test('parsePowerStatus rejects anything else', () => {
  for (const output of ['', 'keep=maybe running=1 secret=saved', 'keep=on running=1 secret=saved extra', 'error: device offline'])
    assert.equal(power.parsePowerStatus(output), null, output);
});

test('newlyReady lists serials that just appeared', () => {
  assert.deepEqual(plain(power.newlyReady(['A'], ['A', 'B'])), ['B']);
  assert.deepEqual(plain(power.newlyReady(['A', 'B'], ['A'])), []);
  assert.deepEqual(plain(power.newlyReady([], ['A'])), ['A']);
});

test('connectedCommand acts only on real connects', () => {
  assert.deepEqual(plain(power.connectedCommand('/p/device-power.sh', ['B'], true, false, false)), ['bash', '/p/device-power.sh', 'connected', '1', '0', 'B']);
  assert.deepEqual(plain(power.connectedCommand('/p/device-power.sh', ['B', 'C'], false, true, false)), ['bash', '/p/device-power.sh', 'connected', '0', '1', 'B', 'C']);
  // A shell restart restores keepers but never wakes or unlocks.
  assert.deepEqual(plain(power.connectedCommand('/p/device-power.sh', ['B'], true, true, true)), ['bash', '/p/device-power.sh', 'connected', '0', '0', 'B']);
  assert.deepEqual(plain(power.connectedCommand('/p/device-power.sh', [], true, true, false)), []);
});

test('secretLabel describes every state', () => {
  for (const secret of ['none', 'saved', 'blocked'])
    assert.notEqual(power.secretLabel(secret), power.secretLabel('unknown'), secret);
});
