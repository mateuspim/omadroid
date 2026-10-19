const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const model = loadJs('Model.js');
const plain = value => JSON.parse(JSON.stringify(value));

test('Android device names replace model codes and keep the model', () => {
  const names = model.parseDeviceNames('USB123\tDesk phone\r\nbad line\n192.168.1.3:5555\t  \n');
  assert.deepEqual(plain(names), { USB123: 'Desk phone' });
  const rows = model.withDeviceNames([{ serial: 'USB123', name: 'Pixel 6' }, { serial: 'OTHER', name: 'SM X730' }], names);
  assert.deepEqual(plain(rows), [{ serial: 'USB123', name: 'Desk phone', model: 'Pixel 6' }, { serial: 'OTHER', name: 'SM X730', model: 'SM X730' }]);
});

test('ADB parses states, model names, transports and ignores daemon chatter', () => {
  const rows = model.parseDevices(`* daemon started successfully\nList of devices attached\nUSB123 device usb:1-2 product:oriole model:Pixel_6 device:oriole transport_id:1\nLOCKED unauthorized usb:1-3\nNOACCESS no permissions (user in plugdev group; are your udev rules wrong?)\n192.168.1.3:5555 offline transport_id:3\nemulator-5554 device product:sdk model:SDK\nadb-PHONE-random._adb-tls-connect._tcp device model:Pixel_9\nUSB123 device\n`);
  assert.equal(rows.length, 6);
  assert.equal(rows[0].name, 'Pixel 6');
  assert.deepEqual(plain(rows.map(r => r.transport)), ['USB', 'USB', 'USB', 'Wireless', 'Emulator', 'Wireless']);
  assert.equal(rows[2].status, 'no permissions');
  assert.equal(rows[3].status, 'offline');
});

test('Avahi records preserve pairing ports, scope IPv6 and deduplicate endpoints', () => {
  const rows = model.parseMdns([
    '=;eno1;IPv4;adb-PHONE-random;_adb-tls-connect._tcp;local;phone.local;192.168.1.3;37001;',
    '=;wlan0;IPv4;adb-PHONE-random;_adb-tls-connect._tcp;local;phone.local;192.168.1.3;37001;',
    '=;eno1;IPv4;adb-PHONE-other;_adb-tls-pairing._tcp;local;phone.local;192.168.1.3;42000;',
    '=;wlan0;IPv6;old;_adb._tcp;local;old.local;fe80::1;5555;',
    '=;eno1;IPv4;noise;_http._tcp;local;other.local;192.168.1.1;80;',
    '=;eno1;IPv4;bad;_adb._tcp;local;other.local;192.168.1.1;99999;',
    '+;eno1;IPv4;unresolved;_adb._tcp;local'
  ].join('\n'));
  assert.equal(rows.length, 3);
  assert.equal(rows[1].pair, true);
  assert.equal(rows[1].endpoint, '192.168.1.3:42000');
  assert.equal(rows[2].endpoint, '[fe80::1%wlan0]:5555');
});

test('pairing prefill reuses the host but never substitutes a connection port', () => {
  const services = model.parseMdns([
    '=;eno1;IPv4;phone-connect;_adb-tls-connect._tcp;local;phone.local;192.168.1.3;37001;',
    '=;eno1;IPv4;phone-pair;_adb-tls-pairing._tcp;local;phone.local;192.168.1.3;42000;',
    '=;wlan0;IPv6;ipv6-connect;_adb-tls-connect._tcp;local;phone6.local;fe80::1;37111;'
  ].join('\n'));
  assert.deepEqual(plain(model.pairingPrefill(services[0], services)), { host: '192.168.1.3', port: '42000' });
  assert.deepEqual(plain(model.pairingPrefill(services[0], [services[0]])), { host: '192.168.1.3', port: '' });
  assert.deepEqual(plain(model.pairingPrefill(services[1], services)), { host: '192.168.1.3', port: '42000' });
  assert.deepEqual(plain(model.pairingPrefill(services[2], services)), { host: '[fe80::1%wlan0]', port: '' });
  assert.equal(model.pairingEndpoint('[fe80::1%wlan0]', '42001'), '[fe80::1%wlan0]:42001');
  assert.equal(model.pairingEndpoint('fe80::1%wlan0', '42001'), '[fe80::1%wlan0]:42001');
});

test('after pairing, the connect port is taken from the same host, never the pairing port', () => {
  const rows = model.parseMdns([
    '=;eno1;IPv4;other;_adb-tls-connect._tcp;local;other.local;192.168.1.9;39000;',
    '=;eno1;IPv4;tab-pair;_adb-tls-pairing._tcp;local;tab.local;192.168.1.5;42000;',
    '=;eno1;IPv4;tab;_adb-tls-connect._tcp;local;tab.local;192.168.1.5;37002;'
  ].join('\n'));
  assert.equal(model.connectEndpointAfterPairing('192.168.1.5:42000', rows), '192.168.1.5:37002');
  assert.equal(model.connectEndpointAfterPairing('192.168.1.7:42000', rows), '');
  assert.equal(model.connectEndpointAfterPairing('192.168.1.5:42000', rows.filter(r => r.pair)), '');
  assert.equal(model.connectEndpointAfterPairing('not an address', rows), '');
  assert.equal(model.connectEndpointAfterPairing('192.168.1.5:42000', undefined), '');
});

test('only a failed discovered wireless connection enters pairing fallback', () => {
  const discovered = model.parseMdns('=;eno1;IPv4;phone;_adb-tls-connect._tcp;local;phone.local;192.168.1.3;37001;')[0];
  assert.equal(model.needsPairingFallback(discovered, true), true);
  assert.equal(model.needsPairingFallback(discovered, false), false);
  assert.equal(model.needsPairingFallback({ ...discovered, pair: true }, true), false);
  assert.equal(model.needsPairingFallback({ ...discovered, source: 'adb', status: 'offline' }, true), false);
});

test('merge matches wireless service or endpoint, keeps USB and pairing', () => {
  const devices = model.parseDevices('PHONE device usb:1 model:Pixel\nadb-PHONE-random._adb-tls-connect._tcp.local. device model:Pixel\n192.168.1.4:5555 offline');
  const services = model.parseMdns('=;eno1;IPv4;adb-PHONE-random;_adb-tls-connect._tcp;local;phone.local;192.168.1.3;37001\n=;eno1;IPv4;adb-PHONE-pair;_adb-tls-pairing._tcp;local;phone.local;192.168.1.3;42000\n=;eno1;IPv4;other;_adb._tcp;local;other.local;192.168.1.4;5555');
  const rows = model.deviceRows(devices, services);
  assert.equal(rows.length, 4);
  assert.equal(rows.filter(r => r.source === 'mdns').length, 1);
  assert.equal(rows.find(r => r.serial.includes('.local.')).endpoint, '192.168.1.3:37001');
  assert.equal(devices[1].endpoint, '');
});

test('a service on the host of a wireless device is that device, whatever the port', () => {
  const tablet = '=;eno1;IPv4;adb-TAB-x;_adb-tls-connect._tcp;local;Android.local;192.168.1.50;34801;"name=SM-X730"';
  // Ready: adb's endpoint is live; the cached advertised port is stale.
  const ready = model.deviceRows(model.parseDevices('192.168.1.50:39357 device model:SM_X730'), model.parseMdns(tablet));
  assert.deepEqual(plain(ready.map(r => [r.source, r.endpoint])), [['adb', '192.168.1.50:39357']]);
  // Offline after a port change: Connect goes to the advertised port.
  const offline = model.deviceRows(model.parseDevices('192.168.1.50:45099 offline'), model.parseMdns(tablet));
  assert.deepEqual(plain(offline.map(r => [r.serial, r.status, r.endpoint])), [['192.168.1.50:45099', 'offline', '192.168.1.50:34801']]);
  // Back on a new port: adb's dead entries for that host are hidden.
  const back = model.deviceRows(model.parseDevices('192.168.1.50:45099 offline\n192.168.1.50:38083 offline\n192.168.1.50:46593 device\n192.168.1.9:5555 offline'), []);
  assert.deepEqual(plain(back.map(r => r.serial)), ['192.168.1.50:46593', '192.168.1.9:5555']);
  // Another host is still its own row.
  const other = model.deviceRows(model.parseDevices('192.168.1.50:39357 device'), model.parseMdns(tablet.replace('192.168.1.50', '192.168.1.20')));
  assert.equal(other.length, 2);
});

test('two ready adb links to one device are one row, the other link kept as an alias', () => {
  const tablet = '=;eno1;IPv4;adb-TAB-x;_adb-tls-connect._tcp;local;Android.local;192.168.1.50;34801;"name=SM-X730"';
  const both = '192.168.1.50:34801 device model:SM_X730\nadb-TAB-x._adb-tls-connect._tcp device model:SM_X730';
  const rows = model.deviceRows(model.parseDevices(both), model.parseMdns(tablet));
  assert.deepEqual(plain(rows.map(r => [r.serial, r.aliases])), [['192.168.1.50:34801', ['adb-TAB-x._adb-tls-connect._tcp']]]);
  // adb's port can differ from Avahi's cached one: one adbd per host.
  const moved = model.deviceRows(model.parseDevices(both.replace(':34801', ':39357')), model.parseMdns(tablet));
  assert.deepEqual(plain(moved.map(r => r.serial)), ['192.168.1.50:39357']);
  // Without the service nothing ties them together, and another device's
  // service doesn't merge them either.
  assert.equal(model.deviceRows(model.parseDevices(both), []).length, 2);
  assert.equal(model.deviceRows(model.parseDevices(both), model.parseMdns(tablet.replace('adb-TAB-x', 'adb-OTHER-y'))).length, 2);
  // An offline mDNS link isn't merged; it stays a row to drop.
  const stale = model.deviceRows(model.parseDevices(both.replace(/(_tcp) device/, '$1 offline')), model.parseMdns(tablet));
  assert.equal(stale.length, 2);
});

test('Avahi decimal escaping preserves service names without treating them as shell code', () => {
  const rows = model.parseMdns(String.raw`=;eno1;IPv4;Phone\032name\059test;_adb-tls-connect._tcp;local;phone.local;192.168.1.2;1234;`);
  assert.equal(rows[0].name, 'Phone name;test');
  assert.equal(rows[0].serial, 'Phone name;test');
  const unicode = model.parseMdns(String.raw`=;eno1;IPv4;Caf\195\169\032100%;_adb._tcp;local;phone.local;192.168.1.2;1234;`);
  assert.equal(unicode[0].name, 'Café 100%');
});

test('endpoints reject invalid ports and command injection', () => {
  for (const value of ['host', 'host:0', 'host:65536', '-bad:123', '127.0.0.999:123', 'host:123;touch /tmp/pwn', '$(id):123', 'host:12\n--help']) assert.equal(model.endpoint(value), '', value);
  assert.equal(model.endpoint(' 192.168.1.2:05555 '), '192.168.1.2:5555');
  assert.equal(model.endpoint('android.local:1234'), 'android.local:1234');
});

test('ADB actions always target one endpoint and never expose a pairing code in argv', () => {
  assert.deepEqual(plain(model.adbCommand('pair', 'phone.local:12345')), ['adb', 'pair', 'phone.local:12345']);
  assert.deepEqual(plain(model.adbCommand('disconnect', 'adb-PHONE-abc._adb-tls-connect._tcp')), ['adb', 'disconnect', 'adb-PHONE-abc._adb-tls-connect._tcp']);
  for (const target of ['', '--help', 'USB123', '; reboot']) assert.throws(() => model.adbCommand('disconnect', target));
  assert.throws(() => model.adbCommand('kill-server', 'phone:1234'));
  assert.equal(model.actionSucceeded('connect', 0, 'failed to connect to phone:1234', ''), false);
  assert.equal(model.actionSucceeded('connect', 0, 'already connected to phone:1234', ''), true);
  assert.equal(model.actionSucceeded('pair', 0, 'Successfully paired to phone:1234 [guid=abc]', ''), true);
  assert.equal(model.actionSucceeded('disconnect', 0, 'disconnected phone:1234', ''), true);
  assert.equal(model.actionSucceeded('connect', 1, 'connected to phone:1234', ''), false);
});

test('scrcpy combines every option and safely preserves serial/path as single arguments', () => {
  const profile = plain(model.builtInProfiles()[0]);
  Object.assign(profile, { audio: false, screenOff: true, fullscreen: true, record: true, codec: 'av1' });
  const path = '/tmp/My recordings/$(no-shell).mkv';
  assert.deepEqual(plain(model.scrcpyCommand('device;literal', profile, path)), ['scrcpy', '--serial=device;literal', '--video-codec=av1', '--video-bit-rate=8M', '--max-size=1920', '--max-fps=60', '--no-audio', '--turn-screen-off', '--keep-active', '--fullscreen', '--record=' + path]);
  Object.assign(profile, { maxSize: '0', fps: '0', audio: true, record: false, fullscreen: false, screenOff: false });
  assert.deepEqual(plain(model.scrcpyCommand('USB', profile, '')), ['scrcpy', '--serial=USB', '--video-codec=av1', '--video-bit-rate=8M']);
  assert.throws(() => model.scrcpyCommand('', profile, ''));
  profile.bitrate = '8; whoami';
  assert.throws(() => model.scrcpyCommand('USB', profile, ''));
});

test('4K and 60 Mbps are passed to scrcpy unchanged, including wireless serials', () => {
  const profile = { ...plain(model.builtInProfiles()[0]), maxSize: '3840', bitrate: '60' };
  assert.deepEqual(plain(model.scrcpyCommand('192.168.1.3:37123', profile, '')), [
    'scrcpy', '--serial=192.168.1.3:37123', '--video-codec=h264',
    '--video-bit-rate=60M', '--max-size=3840', '--max-fps=60'
  ]);
});

test('audio-only runs without a window and records audio as MKA', () => {
  const profile = plain(model.builtInProfiles()[0]);
  assert.deepEqual(plain(model.audioOnlyCommand('USB', profile, '')), ['scrcpy', '--serial=USB', '--no-video', '--no-window']);
  profile.record = true;
  const path = model.recordingPath('/tmp', 'USB', new Date('2026-09-07T20:00:00Z'), 'audio', 'mka');
  assert.match(path, /\.mka$/);
  assert.deepEqual(plain(model.audioOnlyCommand('USB', profile, path)), ['scrcpy', '--serial=USB', '--no-video', '--no-window', '--record=' + path, '--record-format=mka']);
  assert.throws(() => model.audioOnlyCommand('USB', profile, path.replace(/mka$/, 'mkv')));
});

test('saved profiles survive roundtrip and reject corrupt, duplicate and built-in names', () => {
  const p = { ...plain(model.builtInProfiles()[0]), name: 'My phone' };
  assert.deepEqual(plain(model.savedProfiles(JSON.stringify([p, p, { ...p, codec: 'bad' }, model.builtInProfiles()[0]]))), [p]);
  assert.deepEqual(plain(model.savedProfiles('not json')), []);
  assert.deepEqual(plain(model.savedProfiles('{}')), []);
  assert.equal(model.builtInProfiles().every(model.validProfile), true);
});

test('screen-off profiles prevent idle sleep with an explicit opt-out', () => {
  const profile = { ...plain(model.builtInProfiles()[0]), screenOff: true };
  assert.equal(model.preventsIdleSleep(profile), true);
  assert.ok(model.scrcpyCommand('USB', profile, '').includes('--keep-active'));
  profile.keepActive = false;
  assert.equal(model.preventsIdleSleep(profile), false);
  assert.ok(!model.scrcpyCommand('USB', profile, '').includes('--keep-active'));
  profile.screenOff = false;
  profile.keepActive = true;
  assert.ok(model.scrcpyCommand('USB', profile, '').includes('--keep-active'));
  assert.ok(!model.audioOnlyCommand('USB', profile, '').includes('--keep-active'));
});

test('legacy and new profiles preserve screen-power preferences through storage', () => {
  const legacy = { ...plain(model.builtInProfiles()[0]), name: 'Legacy', screenOff: true };
  const optOut = { ...legacy, name: 'Allow idle lock', keepActive: false };
  const invalid = { ...legacy, name: 'Invalid', keepActive: 'yes' };
  const restored = model.savedProfiles(JSON.stringify([legacy, optOut, invalid]));
  assert.deepEqual(plain(restored), [legacy, optOut]);
  assert.equal(model.preventsIdleSleep(restored[0]), true);
  assert.equal(model.preventsIdleSleep(restored[1]), false);
});

test('recording names are unique MKV files and malformed paths fail', () => {
  const date = new Date('2026-09-07T20:00:00Z');
  const a = model.recordingPath('/tmp/My recordings/', '192.168.1.2:1234', date, 'a');
  const b = model.recordingPath('/tmp/My recordings/', '192.168.1.2:1234', date, 'b');
  assert.equal(a, '/tmp/My recordings/OmaDroid-192_168_1_2_1234-2026-09-07T20-00-00-000Z-a.mkv');
  assert.notEqual(a, b);
  assert.throws(() => model.recordingPath('relative', 'USB', date, 'x'));
  assert.throws(() => model.recordingPath('/tmp\ninvalid', 'USB', date, 'x'));
});

test('mDNS resolve timeouts become one hint per unreachable device', () => {
  const timeout = (name, type) => `Failed to resolve service '${name}' of type '${type}' in domain 'local': Timeout reached`;
  const stderr = [timeout('adb-R5CX00TEST1-u940uM', '_adb-tls-connect._tcp'), timeout('adb-R5CX00TEST1-u940uM', '_adb-tls-connect._tcp'),
    timeout('adb-OTHER-abc123', '_adb-tls-connect._tcp'), timeout('adb-AWAKE-x', '_adb-tls-connect._tcp')].join('\n');
  const awake = model.parseMdns('=;eno1;IPv4;adb-AWAKE-x;_adb-tls-connect._tcp;local;a.local;192.168.1.8;37001;');
  const status = model.mdnsStatus(0, stderr, awake, { 'adb-R5CX00TEST1-u940uM': 'SM-X730' });
  assert.equal(status.level, 'warning');
  assert.equal(status.text, "SM-X730 was seen but didn't answer. Wake it and check Wireless debugging is on.\n" +
    "OTHER was seen but didn't answer. Wake it and check Wireless debugging is on.");
  assert.equal(status.details.split('\n').length, 3, 'duplicate IPv4/IPv6 lines are collapsed');
});

test('A service announced over IPv4 and IPv6 is one row, preferring IPv4', () => {
  const rows = model.parseMdns([
    '=;eno1;IPv6;adb-TAB-x;_adb-tls-connect._tcp;local;Android.local;fe80::6dd7:2d81:7c95:c24d;46593;"name=SM-X730"',
    '=;eno1;IPv4;adb-TAB-x;_adb-tls-connect._tcp;local;Android.local;192.168.1.50;46593;"name=SM-X730"',
    '=;eno1;IPv6;adb-TAB-x;_adb-tls-connect._tcp;local;Android.local;fe80::6dd7:2d81:7c95:c24d;46593;"name=SM-X730"',
    '=;eno1;IPv6;adb-SIX-y;_adb._tcp;local;six.local;fe80::2;5555;'
  ].join('\n'));
  assert.deepEqual(plain(rows.map(row => row.endpoint)), ['192.168.1.50:46593', '[fe80::2%eno1]:5555']);
});

test("Avahi's note on being stopped is not a discovery failure", () => {
  assert.deepEqual(plain(model.mdnsStatus(0, 'Got SIGTERM, quitting.\nGot SIGTERM, quitting.', [], {})), { level: '', text: '', details: '' });
});

test('mDNS hard failures are errors; clean and partial scans are not', () => {
  assert.deepEqual(plain(model.mdnsStatus(0, '', [], {})), { level: '', text: '', details: '' });
  const down = model.mdnsStatus(1, 'Failed to create client object: Daemon not running\nOmaDroid mDNS: discovery stopped (_adb._tcp exited with 1). Check that avahi-daemon is running.', [], {});
  assert.equal(down.level, 'error');
  assert.match(down.text, /avahi-daemon/);
  assert.match(down.details, /Daemon not running/);
  assert.equal(model.mdnsStatus(1, 'OmaDroid mDNS: missing avahi-browse. Install Avahi and GNU coreutils.', [], {}).text, 'missing avahi-browse. Install Avahi and GNU coreutils.');
  assert.equal(model.mdnsStatus(124, '', [], {}).level, 'error');
  const stopped = model.mdnsStatus(1, 'OmaDroid mDNS: discovery stopped (_adb-tls-pairing._tcp exited with 1). Check that avahi-daemon is running.', [], {});
  assert.equal(stopped.level, 'error', 'one browser exiting stops the whole stream');
  const partial = model.mdnsStatus(0, 'Pairing resolver failed', [], {});
  assert.equal(partial.level, 'warning');
  assert.match(partial.text, /some devices may be missing/);
});

test('adb track-devices frames split by byte length, across chunks', () => {
  const row = '192.168.1.3:5555\tdevice product:x model:Ünïcode transport_id:1\n';
  const bytes = Buffer.byteLength(row).toString(16).padStart(4, '0');
  const stream = '0000' + bytes + row;
  const first = model.takeTrackFrames(stream.slice(0, 10));
  assert.deepEqual(plain(first.payloads), ['']);
  const second = model.takeTrackFrames(first.rest + stream.slice(10));
  assert.deepEqual(plain(second), { payloads: [row], rest: '' });
  assert.equal(model.parseDevices(second.payloads[0])[0].serial, '192.168.1.3:5555');
  assert.throws(() => model.takeTrackFrames('List of devices'), /4-digit hex length/);
});

test('streamed Avahi lines add, update and remove resolved records', () => {
  const records = {};
  const resolved = '=;eno1;IPv4;adb-X-a;_adb-tls-connect._tcp;local;x.local;192.168.1.4;37001;"name=SM-X730"';
  assert.equal(model.applyMdnsLine(records, '+;eno1;IPv4;adb-X-a;_adb-tls-connect._tcp;local'), false, 'unresolved announcements are ignored');
  assert.equal(model.applyMdnsLine(records, resolved), true);
  assert.equal(model.applyMdnsLine(records, resolved), false, 'a repeat is not a change');
  assert.equal(model.parseMdns(Object.values(records).join('\n'))[0].endpoint, '192.168.1.4:37001');
  assert.equal(model.applyMdnsLine(records, '-;eno1;IPv6;adb-X-a;_adb-tls-connect._tcp;local'), false, 'another protocol is a different record');
  assert.equal(model.applyMdnsLine(records, '-;eno1;IPv4;adb-X-a;_adb-tls-connect._tcp;local'), true);
  assert.deepEqual(plain(records), {});
});

test('sameData compares plain rows by content', () => {
  assert.equal(model.sameData([{ serial: 'A', info: null }], [{ serial: 'A', info: null }]), true);
  assert.equal(model.sameData([{ serial: 'A' }], [{ serial: 'B' }]), false);
});
