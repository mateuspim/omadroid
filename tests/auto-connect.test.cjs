// AutoConnect.js projections. tests/Smoke.qml covers the QML component.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const auto = loadJs('AutoConnect.js');
const plain = value => JSON.parse(JSON.stringify(value));

const service = (name, endpoint) => ({ serial: name, service: '_adb-tls-connect._tcp', endpoint, pair: false });
const phone = service('adb-R5CR123ABC-a1B2c3', '192.168.1.5:37002');
const ready = (serial, endpoint) => ({ serial, status: 'device', transport: 'Wireless', endpoint });

test('deviceKey drops the service suffix', () => {
  assert.equal(auto.deviceKey('adb-R5CR123ABC-a1B2c3'), 'adb-R5CR123ABC');
  assert.equal(auto.deviceKey('adb-SERIAL-WITH-DASHES-xyz'), 'adb-SERIAL-WITH-DASHES');
  assert.equal(auto.deviceKey('studio-phone'), 'studio-phone');
});

test('trustedKeys remembers devices ready over Wi-Fi, by host or service name', () => {
  assert.deepEqual(plain(auto.trustedKeys([ready('192.168.1.5:40001', '192.168.1.5:40001')], [phone])), ['adb-R5CR123ABC']);
  assert.deepEqual(plain(auto.trustedKeys([ready('adb-R5CR123ABC-a1B2c3._adb-tls-connect._tcp', '')], [phone])), ['adb-R5CR123ABC']);
  // Seen but not connected, or connected over USB only: not trusted yet.
  assert.deepEqual(plain(auto.trustedKeys([], [phone])), []);
  assert.deepEqual(plain(auto.trustedKeys([{ serial: 'R5CR123ABC', status: 'device', transport: 'USB', endpoint: '' }], [phone])), []);
  assert.deepEqual(plain(auto.trustedKeys([{ ...ready('192.168.1.5:40001', '192.168.1.5:40001'), status: 'offline' }], [phone])), []);
  // Pairing services never count.
  assert.deepEqual(plain(auto.trustedKeys([ready('192.168.1.5:40001', '192.168.1.5:40001')], [{ ...phone, service: '_adb-tls-pairing._tcp', pair: true }])), []);
});

test('autoConnectTargets picks known, unready, untried endpoints', () => {
  const stranger = service('adb-STRANGER-zz', '192.168.1.9:39000');
  assert.deepEqual(plain(auto.autoConnectTargets([], [phone, stranger], ['adb-R5CR123ABC'], {})), ['192.168.1.5:37002']);
  assert.deepEqual(plain(auto.autoConnectTargets([ready('192.168.1.5:37002', '192.168.1.5:37002')], [phone], ['adb-R5CR123ABC'], {})), [], 'already ready');
  assert.deepEqual(plain(auto.autoConnectTargets([], [phone], ['adb-R5CR123ABC'], { '192.168.1.5:37002': true })), [], 'already tried');
  assert.deepEqual(plain(auto.autoConnectTargets([], [phone], [], {})), [], 'unknown device');
  // A stale offline entry on the old port doesn't block the new one.
  assert.deepEqual(plain(auto.autoConnectTargets([{ ...ready('192.168.1.5:40001', '192.168.1.5:40001'), status: 'offline' }], [phone], ['adb-R5CR123ABC'], {})), ['192.168.1.5:37002']);
});

test('stillAnnounced forgets endpoints that left, so they are tried on return', () => {
  assert.deepEqual(plain(auto.stillAnnounced({ '192.168.1.5:37002': true, '192.168.1.9:1': true }, [phone])), { '192.168.1.5:37002': true });
  assert.deepEqual(plain(auto.stillAnnounced(null, [phone])), {});
});

test('keyAt names the device at an endpoint', () => {
  assert.equal(auto.keyAt([phone], '192.168.1.5:37002'), 'adb-R5CR123ABC');
  assert.equal(auto.keyAt([phone], '192.168.1.5:1'), '');
});

test('rememberKeys merges in order and keeps the newest 50', () => {
  assert.deepEqual(plain(auto.rememberKeys(['adb-A'], ['adb-B', 'adb-A', ''])), ['adb-A', 'adb-B']);
  const many = Array.from({ length: 50 }, (_, i) => `adb-${i}`);
  assert.deepEqual(plain(auto.rememberKeys(many, ['adb-new'])).slice(-2), ['adb-49', 'adb-new']);
  assert.equal(auto.rememberKeys(many, ['adb-new']).length, 50);
});

test('parseKeys accepts only a list of adb keys', () => {
  assert.deepEqual(plain(auto.parseKeys('["adb-R5CR", 7, "other", "adb-"]')), ['adb-R5CR']);
  for (const json of ['', 'nope', '{"a":1}', 'null'])
    assert.deepEqual(plain(auto.parseKeys(json)), [], json);
});

test('refusedTrust separates an untrusted computer from a network failure', () => {
  assert.equal(auto.refusedTrust('failed to authenticate to 192.168.1.5:37002'), true);
  assert.equal(auto.refusedTrust('failed to connect to 192.168.1.5:37002: Connection refused'), false);
  assert.equal(auto.refusedTrust(''), false);
});
