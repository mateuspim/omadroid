// DeviceActions.js and DevicePage.js projections. tests/DevicePreview.qml
// renders the page itself.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const page = loadJs('DevicePage.js');
const registry = loadJs('DeviceActions.js');
const plain = value => JSON.parse(JSON.stringify(value));

const usb = { serial: 'USB123', name: 'Desk phone', model: 'Pixel 6', transport: 'USB', source: 'adb', status: 'device', endpoint: '' };
const wifi = { serial: 'adb-PHONE-random._adb-tls-connect._tcp', name: 'Pixel 9', model: 'Pixel 9', transport: 'Wireless', source: 'adb', status: 'device', endpoint: '192.168.1.4:5555' };
const keys = actions => plain(actions.map(action => action.key));
const find = (actions, key) => actions.find(action => action.key === key);

test('deviceControls offers Go wireless over USB and Disconnect over Wi-Fi', () => {
  assert.deepEqual(keys(registry.deviceControls(usb, {})), ['wake', 'lock', 'keepAwake', 'sendText', 'goWireless']);
  assert.deepEqual(keys(registry.deviceControls(wifi, {})), ['wake', 'lock', 'keepAwake', 'sendText', 'disconnect']);
});

test('deviceControls keeps only Disconnect for a device that is not ready', () => {
  assert.deepEqual(keys(registry.deviceControls(Object.assign({}, wifi, { status: 'offline' }), {})), ['disconnect']);
  assert.deepEqual(keys(registry.deviceControls(Object.assign({}, usb, { status: 'unauthorized' }), {})), []);
});

test('deviceControls entries carry every field the row reads', () => {
  for (const control of registry.deviceControls(usb, { powerKnown: true })) {
    assert.deepEqual(Object.keys(control).sort(), ['enabled', 'icon', 'key', 'label', 'selected', 'tooltip'], control.key);
    assert.ok(control.icon && control.label && control.tooltip, control.key);
  }
});

test('deviceControls labels stay short enough for one row', () => {
  for (const row of [usb, wifi])
    assert.ok(registry.deviceControls(row, { canUnlock: true }).every(control => control.label.length <= 10), row.transport);
});

test('deviceControls reflects power state', () => {
  const idle = registry.deviceControls(usb, {});
  assert.equal(find(idle, 'keepAwake').enabled, false, 'unknown power state cannot be toggled');
  assert.equal(find(idle, 'wake').label, 'Wake');
  const on = registry.deviceControls(usb, { powerKnown: true, keepAwake: true, keepAwakeRunning: false, canUnlock: true });
  assert.equal(find(on, 'keepAwake').selected, true);
  assert.match(find(on, 'keepAwake').tooltip, /not running/);
  assert.equal(find(on, 'wake').label, 'Unlock');
  const busy = registry.deviceControls(usb, { powerKnown: true, powerBusy: true });
  assert.deepEqual(['wake', 'lock', 'keepAwake'].map(key => find(busy, key).enabled), [false, false, false]);
});

test('deviceControls keeps the connection of a session and waits for adb actions', () => {
  assert.equal(find(registry.deviceControls(wifi, { sessionType: 'mirror' }), 'disconnect').enabled, false, 'a running session keeps its connection');
  assert.equal(find(registry.deviceControls(wifi, {}), 'disconnect').enabled, true);
  assert.equal(find(registry.deviceControls(usb, { actionsBusy: true }), 'goWireless').enabled, false);
});

test('deviceControls rejects a missing row with the expected shape', () => {
  assert.throws(() => registry.deviceControls(null, {}), /discovery row/);
});

test('controlState fills every field', () => {
  assert.deepEqual(plain(registry.controlState(undefined)), { keepAwake: false, keepAwakeRunning: false, powerKnown: false, powerBusy: false, canUnlock: false, actionsBusy: false, sessionType: '' });
});

// Session cards: the forms' state, and the machine's one session.
const forms = {
  profileName: 'Balanced', profile: { maxSize: '1920', bitrate: '8', record: false },
  webcam: { camera: 'id:1', size: '1920x1080', fps: '30' }, cameras: [{ id: '1', facing: 'front' }], webcamIssue: ''
};
const idleSession = { busy: false, pid: 0, serial: '', kind: 'mirror', stopping: false, recording: '', pendingKind: '', pendingSerial: '', deviceName: '' };
/** Cards for USB123. Example: cards({ busy: true, pid: 42, serial: 'USB123', kind: 'mirror' }). */
function cards(session, extra) {
  return registry.sessionCards(Object.assign({ serial: 'USB123', missingTools: '', armed: '', forms, session: Object.assign({}, idleSession, session) }, extra));
}

test('sessionCards starts each kind and summarizes what it would start', () => {
  const idle = cards({});
  assert.deepEqual(keys(idle), ['mirror', 'audio', 'webcam']);
  assert.deepEqual(plain(idle.map(card => card.subtitle)), ['Balanced · 1080p · 8 Mbps', 'Opus · no video', 'Front · 1080p · 30 fps']);
  assert.ok(idle.every(card => card.action === 'start' && card.enabled && !card.running && !card.urgent));
  assert.match(find(idle, 'webcam').tooltip, /webcam · Front · 1080p/);
});

test('sessionCards marks the session running here and stops it on click', () => {
  const mirroring = cards({ busy: true, pid: 42, serial: 'USB123', kind: 'mirror' });
  assert.equal(find(mirroring, 'mirror').running, true);
  assert.equal(find(mirroring, 'mirror').subtitle, '● Running');
  assert.equal(find(mirroring, 'mirror').action, 'stop');
  const stopping = cards({ busy: true, pid: 42, serial: 'USB123', kind: 'mirror', stopping: true });
  assert.deepEqual([find(stopping, 'mirror').subtitle, find(stopping, 'mirror').action], ['Stopping…', 'none']);
  assert.equal(find(stopping, 'webcam').action, 'none', 'no switch while the session stops');
});

test('sessionCards switches from another kind or another device', () => {
  const mirroring = cards({ busy: true, pid: 42, serial: 'USB123', kind: 'mirror' });
  assert.deepEqual([find(mirroring, 'webcam').subtitle, find(mirroring, 'webcam').action], ['Switch · stops mirroring', 'start']);
  const elsewhere = cards({ busy: true, pid: 42, serial: 'PIXEL', kind: 'webcam', deviceName: 'Pixel 9' });
  assert.equal(find(elsewhere, 'webcam').subtitle, 'Switch · stops Pixel 9', 'the same kind on another phone switches too');
  assert.equal(find(elsewhere, 'mirror').tooltip, 'Switch · stops the webcam on Pixel 9');
  assert.ok(elsewhere.every(card => card.action === 'start' && !card.running));
});

test('sessionCards asks once more before switching away from a recording', () => {
  const recording = { busy: true, pid: 42, serial: 'USB123', kind: 'mirror', recording: '/home/me/OmaDroid.mkv' };
  assert.equal(find(cards(recording), 'webcam').action, 'arm');
  assert.match(find(cards(recording), 'webcam').tooltip, /recording is finalized/);
  const armed = find(cards(recording, { armed: 'webcam' }), 'webcam');
  assert.deepEqual([armed.subtitle, armed.action, armed.urgent], ['Stop recording & switch?', 'start', true]);
  assert.equal(find(cards(recording, { armed: 'webcam' }), 'audio').action, 'arm', 'only the armed card confirms');
  assert.equal(find(cards(recording, { armed: 'webcam' }), 'mirror').action, 'stop', 'Stop needs no confirm: it finalizes the recording');
});

test('sessionCards shows a pending switch on its target only', () => {
  const switching = cards({ busy: true, pid: 42, serial: 'USB123', kind: 'mirror', stopping: true, pendingKind: 'webcam', pendingSerial: 'USB123' });
  assert.deepEqual([find(switching, 'webcam').subtitle, find(switching, 'webcam').running, find(switching, 'webcam').action], ['Switching…', true, 'none']);
  assert.deepEqual(plain(switching.map(card => card.action)), ['none', 'none', 'none']);
  const toOther = cards({ busy: true, pid: 42, serial: 'USB123', kind: 'mirror', pendingKind: 'webcam', pendingSerial: 'PIXEL' });
  assert.equal(find(toOther, 'webcam').running, false, 'a switch to another phone is not this card');
});

test('sessionCards waits while a session starts', () => {
  const starting = cards({ busy: true, pid: 0, serial: 'USB123', kind: 'mirror' });
  assert.deepEqual([find(starting, 'mirror').subtitle, find(starting, 'mirror').running, find(starting, 'mirror').action], ['Starting…', true, 'none']);
  assert.ok(['audio', 'webcam'].every(key => find(starting, key).action === 'none' && !find(starting, key).enabled), 'no switch before the session runs');
  const elsewhere = cards({ busy: true, pid: 0, serial: 'PIXEL', kind: 'webcam' });
  assert.ok(elsewhere.every(card => card.action === 'none' && !card.running));
});

test('sessionCards blocks starts on missing tools and sends an unset webcam to its options', () => {
  const missing = cards({}, { missingTools: 'scrcpy' });
  assert.ok(missing.every(card => card.action === 'none' && !card.enabled));
  assert.match(find(missing, 'mirror').tooltip, /Install scrcpy/);
  const noOutput = find(cards({}, { forms: Object.assign({}, forms, { webcamIssue: 'missing-package' }) }), 'webcam');
  assert.deepEqual([noOutput.subtitle, noOutput.action], ['Needs setup', 'options']);
});

test('sessionCards rejects a state without forms or session', () => {
  assert.throws(() => registry.sessionCards({ serial: 'USB123' }), /\{serial, forms, session\}/);
});

test('session summaries describe profile, audio and camera', () => {
  assert.equal(registry.mirrorSummary('High quality', { maxSize: '0', bitrate: '20', record: true }), 'High quality · Native · 20 Mbps · Rec');
  assert.equal(registry.mirrorSummary('Balanced', null), '');
  assert.equal(registry.audioSummary({ record: true }), 'Opus · records MKA');
  assert.equal(registry.webcamCardSummary({ camera: 'back', size: 'auto', fps: '24' }, null), 'Back · Auto · 24 fps');
  assert.equal(registry.webcamCardSummary({ camera: 'id:2', size: '2032x1144', fps: '30' }, null), 'Camera 2 · 2032×1144 · 30 fps');
});

test('cameraShortName and runningName name a camera and a session kind', () => {
  assert.equal(registry.cameraShortName('id:0', [{ id: '0', facing: 'back' }]), 'Back');
  assert.equal(registry.cameraShortName('id:7', [{ id: '0', facing: 'back' }]), 'Camera 7');
  assert.equal(registry.runningName('audio'), 'audio');
  assert.equal(registry.runningName('bogus'), 'the session');
  assert.deepEqual(plain(registry.sessionRegistry().map(entry => entry.key)), ['mirror', 'audio', 'webcam']);
});

test('deviceSections and pageSection keep the switcher to known sections', () => {
  assert.deepEqual(plain(page.deviceSections()).map(s => s.value), ['sound', 'info']);
  assert.equal(page.pageSection('info'), 'info');
  assert.equal(page.pageSection('bogus'), 'sound');
  // Remembered before Mirror and Webcam became cards.
  assert.equal(page.pageSection('mirror'), 'sound');
  assert.equal(page.pageSection('webcam'), 'sound');
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
