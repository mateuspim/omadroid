// DeviceActions.js and DevicePage.js projections. tests/DevicePreview.qml
// renders the page itself.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
// QML's `.import "Model.js" as Model` becomes a Model namespace here.
const Model = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Model.js`, 'utf8'), Model);
const page = vm.createContext({ Model });
vm.runInContext(readFileSync(`${__dirname}/../DevicePage.js`, 'utf8').replace(/^\.import .*$/m, ''), page);
const registry = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../DeviceActions.js`, 'utf8'), registry);
const plain = value => JSON.parse(JSON.stringify(value));

const usb = { serial: 'USB123', name: 'Desk phone', model: 'Pixel 6', transport: 'USB', source: 'adb', status: 'device', endpoint: '' };
const wifi = { serial: 'adb-PHONE-random._adb-tls-connect._tcp', name: 'Pixel 9', model: 'Pixel 9', transport: 'Wireless', source: 'adb', status: 'device', endpoint: '192.168.1.4:5555' };
const keys = actions => plain(actions.map(action => action.key));
const find = (actions, key) => actions.find(action => action.key === key);

test('deviceActions offers Go wireless over USB and Disconnect over Wi-Fi', () => {
  assert.deepEqual(keys(registry.deviceActions(usb, {})), ['mirror', 'audio', 'wake', 'lock', 'keepAwake', 'sendText', 'goWireless']);
  assert.deepEqual(keys(registry.deviceActions(wifi, {})), ['mirror', 'audio', 'wake', 'lock', 'keepAwake', 'sendText', 'disconnect']);
});

test('deviceActions keeps only Disconnect for a device that is not ready', () => {
  assert.deepEqual(keys(registry.deviceActions(Object.assign({}, wifi, { status: 'offline' }), {})), ['disconnect']);
  assert.deepEqual(keys(registry.deviceActions(Object.assign({}, usb, { status: 'unauthorized' }), {})), []);
});

test('deviceActions entries carry every field the grid reads', () => {
  for (const action of registry.deviceActions(usb, { powerKnown: true })) {
    assert.deepEqual(Object.keys(action).sort(), ['enabled', 'icon', 'key', 'label', 'selected', 'tooltip'], action.key);
    assert.ok(action.icon && action.label && action.tooltip, action.key);
  }
});

test('deviceActions reflects power state', () => {
  const idle = registry.deviceActions(usb, {});
  assert.equal(find(idle, 'keepAwake').enabled, false, 'unknown power state cannot be toggled');
  assert.equal(find(idle, 'wake').label, 'Wake');
  const on = registry.deviceActions(usb, { powerKnown: true, keepAwake: true, keepAwakeRunning: false, canUnlock: true });
  assert.equal(find(on, 'keepAwake').selected, true);
  assert.match(find(on, 'keepAwake').tooltip, /not running/);
  assert.equal(find(on, 'wake').label, 'Unlock');
  const busy = registry.deviceActions(usb, { powerKnown: true, powerBusy: true });
  assert.deepEqual(['wake', 'lock', 'keepAwake'].map(key => find(busy, key).enabled), [false, false, false]);
});

test('deviceActions reflects sessions and running adb actions', () => {
  const mirroring = registry.deviceActions(wifi, { sessionType: 'mirror' });
  assert.equal(find(mirroring, 'mirror').selected, true);
  assert.equal(find(mirroring, 'audio').selected, false);
  assert.equal(find(mirroring, 'disconnect').enabled, false, 'a running session keeps its connection');
  assert.equal(find(registry.deviceActions(wifi, { sessionBusy: true }), 'mirror').enabled, false);
  assert.equal(find(registry.deviceActions(usb, { actionsBusy: true }), 'goWireless').enabled, false);
});

test('deviceActions rejects a missing row with the expected shape', () => {
  assert.throws(() => registry.deviceActions(null, {}), /discovery row/);
});

test('deviceSections and pageSection keep the switcher to known sections', () => {
  assert.deepEqual(plain(page.deviceSections()).map(s => s.value), ['mirror', 'webcam', 'sound', 'info']);
  assert.equal(page.pageSection('info'), 'info');
  assert.equal(page.pageSection('bogus'), 'mirror');
});

test('heroMeta names model, Android and transport, and the status when not ready', () => {
  assert.equal(page.heroMeta(Object.assign({}, usb, { info: { android: '16' } })), 'Pixel 6 · Android 16 · USB');
  assert.equal(page.heroMeta(Object.assign({}, wifi, { info: null })), 'Wireless');
  assert.equal(page.heroMeta(Object.assign({}, usb, { status: 'unauthorized', info: null })), 'Pixel 6 · USB · Authorization needed');
});

test('heroStats shows battery, storage and memory', () => {
  const info = { battery: { level: 64, status: 2 }, internal: { usedKb: 132812500, totalKb: 233398437 }, memKb: 7812500 };
  assert.equal(page.heroStats(info), '64% ⚡ · 136/239 GB · 8 GB RAM');
  assert.equal(page.heroStats({ battery: { level: 80, status: 3 } }), '80%');
  assert.equal(page.heroStats(null), '');
});

test('storageShort keeps both units when they differ', () => {
  assert.equal(page.storageShort({ usedKb: 122373248, totalKb: 999842816 }), '125 GB/1.02 TB');
});

test('identityRows lists the serial and a differing address', () => {
  assert.deepEqual(plain(page.identityRows(usb)), [{ label: 'Serial', value: 'USB123' }]);
  assert.deepEqual(plain(page.identityRows(wifi)), [{ label: 'Serial', value: wifi.serial }, { label: 'Address', value: '192.168.1.4:5555' }]);
  assert.equal(page.identityRows({ serial: 'adb-X', source: 'mdns', endpoint: 'adb-X' })[0].label, 'Service');
});
