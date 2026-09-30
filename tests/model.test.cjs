const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const model = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Model.js`, 'utf8'), model);
const plain = value => JSON.parse(JSON.stringify(value));

test('Android device names replace model codes and keep the model', () => {
  const names = model.parseDeviceNames('USB123\tDesk phone\r\nbad line\n192.168.1.3:5555\t  \n');
  assert.deepEqual(plain(names), { USB123: 'Desk phone' });
  const rows = model.withDeviceNames([{ serial: 'USB123', name: 'Pixel 6' }, { serial: 'OTHER', name: 'SM X730' }], names);
  assert.deepEqual(plain(rows), [{ serial: 'USB123', name: 'Desk phone', model: 'Pixel 6' }, { serial: 'OTHER', name: 'SM X730', model: 'SM X730' }]);
});

test('device-info.sh reads only the current battery state and finds external volumes (fake adb)', () => {
  const { spawnSync } = require('node:child_process');
  const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'droidlink info fixture-'));
  try {
    fs.copyFileSync(`${__dirname}/mock-adb.sh`, path.join(dir, 'adb'));
    fs.chmodSync(path.join(dir, 'adb'), 0o700);
    const result = spawnSync('bash', [`${__dirname}/../device-info.sh`, 'USB123', 'SILENT'], {
      encoding: 'utf8', timeout: 10000, env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH } });
    assert.equal(result.status, 0, result.stderr);
    const info = model.parseDeviceInfo(result.stdout);
    assert.deepEqual(Object.keys(info), ['USB123'], 'a silent device prints nothing');
    assert.deepEqual(plain(info.USB123), {
      external: [{ id: '7934-B54D', kind: 'sd', usedKb: 122373248, totalKb: 999842816 }],
      battery: { status: 2, level: 64, temp: 301, plugged: ['usb'] }, android: '16', sdk: 36, memKb: 11788072,
      screen: { width: 1600, height: 2560 }, internal: { usedKb: 133125120, totalKb: 233775104 } });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('device details format battery, storage, memory and aspect ratio', () => {
  const info = model.parseDeviceInfo([
    'T\tbattery_level\t71', 'T\tbattery_status\t3', 'T\tbattery_temp\t301', 'T\tandroid\t16', 'T\tsdk\t36',
    'T\tmem_kb\t11788072', 'T\tscreen\t1600x2560', 'T\tinternal\t133125120:233775104',
    'T\texternal_A\tA:usb:1048576:31457280', 'T\texternal_B\tB:usb:0:1048576', 'T\tbogus', ''].join('\n')).T;
  assert.equal(model.deviceSummary(info), 'Battery 71 % · Android 16 · 136/239 GB used');
  assert.deepEqual(plain(model.deviceDetails(info)), [
    { label: 'Battery', value: '71 % · on battery · 30.1 °C' },
    { label: 'Android', value: '16 (SDK 36)' },
    { label: 'Internal storage', value: '136 GB of 239 GB used (57 %)' },
    { label: 'USB drive A', value: '1.1 GB of 32.2 GB used (3 %)' },
    { label: 'USB drive B', value: '0 MB of 1.1 GB used (0 %)' },
    { label: 'Memory', value: '12.1 GB' },
    { label: 'Screen', value: '1600 × 2560 · 16:10' }]);
  assert.equal(model.batteryLabel({ level: 100, status: 5 }), '100 % · full');
  assert.equal(model.deviceDetails({ battery: { level: 95, status: 2, plugged: ['ac'] } })[0].value, '95 % · charging (AC)');
  assert.deepEqual([999842816, 122373248, 500].map(model.formatSize), ['1.02 TB', '125 GB', '1 MB']);
  assert.equal(model.deviceSummary({ internal: { usedKb: 122373248, totalKb: 999842816 } }), '125 GB/1.02 TB used');
  assert.deepEqual([[1080, 2400], [1440, 3120], [1920, 1080], [1536, 2048], [1000, 999]].map(([w, h]) => model.aspectRatio(w, h)),
    ['20:9', '19.5:9', '16:9', '4:3', '1.00:1']);
  assert.equal(model.deviceSummary(null), '');
  assert.deepEqual(plain(model.withDeviceInfo([{ serial: 'T' }, { serial: 'X' }], { T: { android: '16' } })),
    [{ serial: 'T', info: { android: '16' } }, { serial: 'X', info: null }]);
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

test('merge only matches exact wireless service or endpoint, keeps USB and pairing', () => {
  const devices = model.parseDevices('PHONE device usb:1 model:Pixel\nadb-PHONE-random._adb-tls-connect._tcp.local. device model:Pixel\n192.168.1.4:5555 offline');
  const services = model.parseMdns('=;eno1;IPv4;adb-PHONE-random;_adb-tls-connect._tcp;local;phone.local;192.168.1.3;37001\n=;eno1;IPv4;adb-PHONE-pair;_adb-tls-pairing._tcp;local;phone.local;192.168.1.3;42000\n=;eno1;IPv4;other;_adb._tcp;local;other.local;192.168.1.4;5555');
  const rows = model.deviceRows(devices, services);
  assert.equal(rows.length, 4);
  assert.equal(rows.filter(r => r.source === 'mdns').length, 1);
  assert.equal(rows.find(r => r.serial.includes('.local.')).endpoint, '192.168.1.3:37001');
  assert.equal(devices[1].endpoint, '');
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
  assert.equal(a, '/tmp/My recordings/DroidLink-192_168_1_2_1234-2026-09-07T20-00-00-000Z-a.mkv');
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

test('mDNS hard failures are errors; clean and partial scans are not', () => {
  assert.deepEqual(plain(model.mdnsStatus(0, '', [], {})), { level: '', text: '', details: '' });
  const down = model.mdnsStatus(1, 'Failed to create client object: Daemon not running\nDroidLink mDNS: _adb._tcp discovery failed. Check that avahi-daemon is running.', [], {});
  assert.equal(down.level, 'error');
  assert.match(down.text, /avahi-daemon/);
  assert.match(down.details, /Daemon not running/);
  assert.equal(model.mdnsStatus(1, 'DroidLink mDNS: missing avahi-browse. Install Avahi and GNU coreutils.', [], {}).text, 'missing avahi-browse. Install Avahi and GNU coreutils.');
  assert.equal(model.mdnsStatus(124, '', [], {}).level, 'error');
  const partial = model.mdnsStatus(1, 'Pairing resolver failed\nDroidLink mDNS: _adb-tls-pairing._tcp discovery failed. Check that avahi-daemon is running.', [], {});
  assert.equal(partial.level, 'warning');
  assert.match(partial.text, /some devices may be missing/);
});
