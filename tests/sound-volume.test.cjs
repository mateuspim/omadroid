// SoundVolume.js projections. tests/device-volume.sh covers device-volume.sh itself.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const sound = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../SoundVolume.js`, 'utf8'), sound);
const plain = (value) => JSON.parse(JSON.stringify(value));
// device-volume.sh status of the Tab S11 on 2026-10-16.
const tabStatus = [
  'mode samsung', 'master 0', 'ringer silent',
  'stream call 0 9 1 15 0', 'stream system 1 0 0 15 1', 'stream media 3 13 0 15 0', 'stream assistant 11 7 0 15 0',
  'app 10067 paused 100 0 com.samsung.android.app.clockpack com.samsung.android.app.clockpack',
  'app 10360 playing 10 0 com.HoYoverse.hkrpgoversea Honkai: Star Rail',
].join('\n');

test('parseVolumeStatus reads every line kind', () => {
  const status = plain(sound.parseVolumeStatus(tabStatus + '\n'));
  assert.equal(status.mode, 'samsung');
  assert.equal(status.master, false);
  assert.equal(status.ringer, 'silent');
  // Listed in page order, not status order.
  assert.deepEqual(status.streams.map((s) => s.key), ['media', 'call', 'system', 'assistant']);
  assert.deepEqual(status.streams[0], { key: 'media', index: 3, volume: 13, min: 0, max: 15, muted: false, label: 'Media' });
  assert.deepEqual(status.apps[1], { uid: 10360, playing: true, volume: 10, muted: false, package: 'com.HoYoverse.hkrpgoversea', label: 'Honkai: Star Rail' });
});

test('parseVolumeStatus keeps unknown values as null', () => {
  const status = plain(sound.parseVolumeStatus('mode appops\nmaster -\nringer -\napp 10360 playing - - com.x Game'));
  assert.equal(status.master, null);
  assert.equal(status.ringer, '');
  assert.deepEqual(status.apps[0], { uid: 10360, playing: true, volume: null, muted: null, package: 'com.x', label: 'Game' });
});

test('parseVolumeStatus rejects output without a mode and skips unknown streams', () => {
  assert.equal(sound.parseVolumeStatus(''), null);
  assert.equal(sound.parseVolumeStatus("adb: device 'X' not found"), null);
  assert.deepEqual(plain(sound.parseVolumeStatus('mode samsung\nstream dtmf 8 1 0 15 0').streams), []);
});

test('visibleApps keeps playing, named or changed apps, playing first', () => {
  const apps = sound.parseVolumeStatus(tabStatus + '\napp 10200 paused 100 0 com.google.android.youtube YouTube\napp 10085 paused 30 0 com.tools com.tools').apps;
  assert.deepEqual(plain(sound.visibleApps(apps)).map((app) => app.uid), [10360, 10085, 10200]);
  assert.deepEqual(plain(sound.visibleApps([{ playing: false, label: 'com.x', package: 'com.x', volume: null, muted: true }])).length, 1);
});

test('withChange updates one row of a copy', () => {
  const status = sound.parseVolumeStatus(tabStatus);
  const changed = sound.withChange(status, 'app', 10360, { volume: 40 });
  assert.equal(changed.apps[1].volume, 40);
  assert.equal(status.apps[1].volume, 10);
  assert.equal(sound.withChange(status, 'stream', 'media', { muted: true }).streams[0].muted, true);
  assert.equal(sound.withChange(null, 'app', 1, {}), null);
});

test('volumeText shows percent, steps or Muted', () => {
  assert.equal(sound.volumeText(13, 15, false), '13/15');
  assert.equal(sound.volumeText(40, 100, false), '40%');
  assert.equal(sound.volumeText(40, 100, true), 'Muted');
});

test('pickVolumeTarget keeps a ready choice, else the first ready device', () => {
  const devices = [{ serial: 'OFF', status: 'offline' }, { serial: 'A', status: 'device' }, { serial: 'B', status: 'device' }];
  assert.equal(sound.pickVolumeTarget(devices, 'B'), 'B');
  assert.equal(sound.pickVolumeTarget(devices, 'OFF'), 'A');
  assert.equal(sound.pickVolumeTarget(devices, ''), 'A');
  assert.equal(sound.pickVolumeTarget([], 'A'), '');
});

test('queueChange replaces a waiting volume of the same target only', () => {
  const set = (kind, id, value) => ['bash', 'v.sh', kind, 'S', id, 'set', value];
  const mute = ['bash', 'v.sh', 'stream', 'S', 'media', 'mute'];
  let queue = sound.queueChange([], set('app', '10360', '35'));
  queue = sound.queueChange(queue, mute);
  queue = sound.queueChange(queue, set('app', '10360', '40'));
  queue = sound.queueChange(queue, set('stream', 'media', '5'));
  assert.deepEqual(plain(queue), [mute, set('app', '10360', '40'), set('stream', 'media', '5')]);
  // Toggles are never merged: two clicks are two changes.
  assert.equal(sound.queueChange([mute], mute).length, 2);
});
