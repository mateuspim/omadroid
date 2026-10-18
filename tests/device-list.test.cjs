const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const list = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../DeviceListModel.js`, 'utf8'), list);
const plain = value => JSON.parse(JSON.stringify(value));

// Rows shaped like Discovery.rows for the smoke fixtures (tests/mock-adb.sh, mock-avahi-browse.sh).
class FixtureRows {
  static usb(info) { return { key: 'adb:USB123', name: 'Desk phone', model: 'Pixel 6', serial: 'USB123', status: 'device', transport: 'USB', endpoint: '', source: 'adb', pair: false, info: info || null }; }
  static wireless() { return { key: 'adb:w', name: 'Pixel 9', model: 'Pixel 9', serial: 'adb-PHONE-random._adb-tls-connect._tcp', status: 'device', transport: 'Wireless', endpoint: '192.168.1.4:37001', source: 'adb', pair: false, info: null }; }
  static unauthorized() { return { key: 'adb:LOCKED', name: 'LOCKED', model: 'LOCKED', serial: 'LOCKED', status: 'unauthorized', transport: 'USB', endpoint: '', source: 'adb', pair: false }; }
  static offline() { return { key: 'adb:off', name: '192.168.1.3:5555', model: '192.168.1.3:5555', serial: '192.168.1.3:5555', status: 'offline', transport: 'Wireless', endpoint: '192.168.1.3:5555', source: 'adb', pair: false }; }
  static nearby() { return { key: 'mdns:c', name: 'adb-NEW-random', serial: 'adb-NEW-random', model: 'SM-X730', status: 'discovered', transport: 'Wireless', endpoint: '192.168.1.5:37002', source: 'mdns', pair: false }; }
  static pairing() { return { key: 'mdns:p', name: 'adb-NEW-pair', serial: 'adb-NEW-pair', model: '', status: 'pairing', transport: 'Wireless', endpoint: '192.168.1.5:42000', source: 'mdns', pair: true }; }
  static all() { return [this.usb(), this.wireless(), this.unauthorized(), this.offline(), this.nearby(), this.pairing()]; }
}

test('deviceGroupKey sorts rows into connected, attention and nearby', () => {
  assert.deepEqual(FixtureRows.all().map(row => list.deviceGroupKey(row)), ['connected', 'connected', 'attention', 'attention', 'nearby', 'nearby']);
});

test('deviceGroups keeps section order and drops empty sections', () => {
  const groups = plain(list.deviceGroups(FixtureRows.all()));
  assert.deepEqual(groups.map(g => [g.key, g.title, g.rows.map(r => r.key)]), [
    ['connected', 'CONNECTED', ['adb:USB123', 'adb:w']],
    ['attention', 'NEEDS ATTENTION', ['adb:LOCKED', 'adb:off']],
    ['nearby', 'NEARBY', ['mdns:c', 'mdns:p']]]);
  assert.deepEqual(plain(list.deviceGroups([FixtureRows.nearby(), FixtureRows.usb()])).map(g => g.key), ['connected', 'nearby']);
  assert.deepEqual(plain(list.deviceGroups([])), []);
  assert.deepEqual(plain(list.deviceGroups(undefined)), []);
});

test('shortBattery shows the level and a bolt while on power', () => {
  assert.equal(list.shortBattery({ level: 64, status: 2 }), '64% 󱐋');
  assert.equal(list.shortBattery({ level: 100, status: 5 }), '100% 󱐋');
  assert.equal(list.shortBattery({ level: 41, status: 3 }), '41%');
  assert.equal(list.shortBattery({}), '');
  assert.equal(list.shortBattery(undefined), '');
});

test('transportName uses everyday words', () => {
  assert.equal(list.transportName(FixtureRows.wireless()), 'Wi-Fi');
  assert.equal(list.transportName(FixtureRows.usb()), 'USB');
  assert.equal(list.transportName({ transport: 'Emulator' }), 'Emulator');
});

test('deviceSubtitle is one short line per state', () => {
  assert.equal(list.deviceSubtitle(FixtureRows.usb({ battery: { level: 64, status: 2 } })), 'Pixel 6 · 64% 󱐋');
  assert.equal(list.deviceSubtitle(FixtureRows.usb()), 'Pixel 6');
  // Same model and name: the transport stands in so the line is never empty.
  assert.equal(list.deviceSubtitle(FixtureRows.wireless()), 'Wi-Fi');
  assert.equal(list.deviceSubtitle(FixtureRows.unauthorized()), 'Accept the USB debugging prompt');
  assert.equal(list.deviceSubtitle(FixtureRows.offline()), 'Offline');
  assert.equal(list.deviceSubtitle(Object.assign(FixtureRows.unauthorized(), { status: 'no permissions' })), 'USB permission needed');
  assert.equal(list.deviceSubtitle(Object.assign(FixtureRows.unauthorized(), { status: 'host' })), 'Host');
  assert.equal(list.deviceSubtitle(FixtureRows.nearby()), 'SM-X730 · Wi-Fi');
  assert.equal(list.deviceSubtitle(FixtureRows.pairing()), 'Wi-Fi · pairing code');
});

test('transportGlyph picks USB, Wi-Fi, Wi-Fi off or emulator', () => {
  assert.equal(list.transportGlyph(FixtureRows.usb()), '󰕓');
  assert.equal(list.transportGlyph(FixtureRows.wireless()), '󰖩');
  assert.equal(list.transportGlyph(FixtureRows.offline()), '󰖪');
  assert.equal(list.transportGlyph({ transport: 'Emulator', status: 'device' }), '󰍹');
});

test('deviceRowAction offers one inline action per row', () => {
  const kinds = FixtureRows.all().map(row => list.deviceRowAction(row).kind);
  assert.deepEqual(kinds, ['open', 'open', '', 'reconnect', 'connect', 'pair']);
  const stale = Object.assign(FixtureRows.offline(), { serial: 'adb-X._adb-tls-connect._tcp', endpoint: '' });
  assert.equal(list.deviceRowAction(stale).kind, 'disconnect');
  assert.equal(list.deviceRowAction(Object.assign(FixtureRows.offline(), { status: 'connecting' })).kind, '');
  assert.equal(list.deviceRowAction(FixtureRows.offline()).tooltip, 'Reconnect to 192.168.1.3:5555');
});

test('deviceRowTooltip carries the serial and a distinct address', () => {
  assert.equal(list.deviceRowTooltip(FixtureRows.usb()), 'Serial USB123');
  assert.equal(list.deviceRowTooltip(FixtureRows.offline()), 'Serial 192.168.1.3:5555');
  assert.equal(list.deviceRowTooltip(FixtureRows.wireless()), 'Serial adb-PHONE-random._adb-tls-connect._tcp\nAddress 192.168.1.4:37001');
  assert.equal(list.deviceRowTooltip(FixtureRows.nearby()), 'Service adb-NEW-random\nAddress 192.168.1.5:37002');
});

test('homeSubtitle counts each non-empty section', () => {
  assert.equal(list.homeSubtitle(FixtureRows.all()), '2 ready · 2 need attention · 2 nearby');
  assert.equal(list.homeSubtitle([FixtureRows.usb()]), '1 ready');
  assert.equal(list.homeSubtitle([]), '0 ready');
});

test('refreshTooltip says how fresh the list is', () => {
  assert.equal(list.refreshTooltip({ tracking: true, updatedAt: '14:02' }), 'Refresh devices (F5)\nFollowing devices live · updated 14:02');
  assert.equal(list.refreshTooltip({ busy: true }), 'Refresh devices (F5)\nDiscovering devices…');
  assert.equal(list.refreshTooltip({ tracking: false, updatedAt: '', intervalSec: 5 }), 'Refresh devices (F5)\nLast scan pending · every 5s');
});

test('sessionBannerText names the session kind and device', () => {
  assert.equal(list.sessionBannerText('mirror', 'Desk phone'), '▶ Mirroring · Desk phone');
  assert.equal(list.sessionBannerText('webcam', 'Desk phone'), '● Webcam · Desk phone');
  assert.equal(list.sessionBannerText('audio', ''), '♪ Audio');
  assert.equal(list.sessionBannerText('unknown', 'X'), '▶ Mirroring · X');
});
