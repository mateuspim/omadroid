// SoundVolume.js projections. tests/device-volume.sh covers device-volume.sh itself.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const sound = loadJs('SoundVolume.js');
const plain = (value) => JSON.parse(JSON.stringify(value));
// device-volume.sh status of the Tab S11 on 2026-10-16.
const tabStatus = [
  'mode samsung', 'master 0', 'ringer silent',
  'stream call 0 9 1 15 0', 'stream system 1 0 0 15 1', 'stream media 3 13 0 15 0', 'stream assistant 11 7 0 15 0',
  'app 10067 paused 100 0 com.example.clock com.example.clock',
  'app 10360 playing 10 0 com.example.starship Starship: Demo Game',
].join('\n');

test('parseVolumeStatus reads every line kind', () => {
  const status = plain(sound.parseVolumeStatus(tabStatus + '\n'));
  assert.equal(status.mode, 'samsung');
  assert.equal(status.master, false);
  assert.equal(status.ringer, 'silent');
  // Listed in page order, not status order.
  assert.deepEqual(status.streams.map((s) => s.key), ['media', 'call', 'system', 'assistant']);
  assert.deepEqual(status.streams[0], { key: 'media', index: 3, volume: 13, min: 0, max: 15, muted: false, label: 'Media' });
  assert.deepEqual(status.apps[1], { uid: 10360, playing: true, volume: 10, muted: false, package: 'com.example.starship', label: 'Starship: Demo Game', naming: false });
});

test('parseVolumeStatus keeps unknown values as null', () => {
  const status = plain(sound.parseVolumeStatus('mode appops\nmaster -\nringer -\napp 10360 playing - - com.x Game'));
  assert.equal(status.master, null);
  assert.equal(status.ringer, '');
  assert.deepEqual(status.apps[0], { uid: 10360, playing: true, volume: null, muted: null, package: 'com.x', label: 'Game', naming: false });
});

test('parseVolumeStatus rejects output without a mode and skips unknown streams', () => {
  assert.equal(sound.parseVolumeStatus(''), null);
  assert.equal(sound.parseVolumeStatus("adb: device 'X' not found"), null);
  assert.deepEqual(plain(sound.parseVolumeStatus('mode samsung\nstream dtmf 8 1 0 15 0').streams), []);
});

test('visibleApps keeps playing, named or changed apps, playing first', () => {
  const apps = sound.parseVolumeStatus(tabStatus + '\napp 10200 paused 100 0 com.example.videos Videos\napp 10085 paused 30 0 com.tools com.tools').apps;
  assert.deepEqual(plain(sound.visibleApps(apps)).map((app) => app.uid), [10360, 10085, 10200]);
  assert.deepEqual(plain(sound.visibleApps([{ playing: false, label: 'com.x', package: 'com.x', volume: null, muted: true }])).length, 1);
});

test('parseVolumeStatus marks apps whose name is being read', () => {
  const apps = sound.parseVolumeStatus(tabStatus + '\nnaming 10067\nnaming 99999').apps;
  assert.deepEqual(plain(apps).map((app) => [app.uid, app.naming]), [[10067, true], [10360, false]]);
  // A paused app waiting for its name keeps its row, so it doesn't pop in later.
  assert.deepEqual(plain(sound.visibleApps(apps)).map((app) => app.uid), [10360, 10067]);
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

test('statusReadApplies drops reads for another device or before a change', () => {
  const now = { serial: 'A', changes: 2, changing: false };
  assert.equal(sound.statusReadApplies({ serial: 'A', changes: 2 }, now), true);
  assert.equal(sound.statusReadApplies({ serial: 'B', changes: 2 }, now), false);
  assert.equal(sound.statusReadApplies({ serial: 'A', changes: 1 }, now), false);
  assert.equal(sound.statusReadApplies({ serial: 'A', changes: 2 }, { serial: 'A', changes: 2, changing: true }), false);
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

// A ListModel stand-in that records each row's identity, as a Repeater's
// delegate would be tied to it.
function fakeRowModel(keys) {
  const rows = keys.map((rowKey) => ({ rowKey }));
  return {
    rows,
    get count() { return rows.length; },
    get: (index) => rows[index],
    move: (from, to, n) => rows.splice(to, 0, ...rows.splice(from, n)),
    insert: (index, row) => rows.splice(index, 0, { ...row }),
    remove: (index, n) => rows.splice(index, n),
  };
}

test('syncRowKeys reorders, adds and drops rows, keeping the rows that stay', () => {
  const model = fakeRowModel(['10085', '1000', '10360']);
  const [gamebar, , game] = model.rows;
  sound.syncRowKeys(model, ['10360', '10400', '10085']);
  assert.deepEqual(model.rows.map((row) => row.rowKey), ['10360', '10400', '10085']);
  assert.equal(model.rows[0], game);
  assert.equal(model.rows[2], gamebar);
  sound.syncRowKeys(model, []);
  assert.equal(model.count, 0);
});

test('syncRowKeys leaves an unchanged list untouched', () => {
  const model = fakeRowModel(['media', 'ring']);
  const before = [...model.rows];
  sound.syncRowKeys(model, ['media', 'ring']);
  assert.deepEqual(model.rows, before);
  assert.equal(model.rows[0], before[0]);
});
