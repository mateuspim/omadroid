// DeviceInfo.js projections, and device-info.sh against the fake adb.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const deviceInfo = loadJs('DeviceInfo.js');
const plain = value => JSON.parse(JSON.stringify(value));

test('device-info.sh reads only the current battery state and finds external volumes (fake adb)', () => {
  const { spawnSync } = require('node:child_process');
  const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omadroid info fixture-'));
  try {
    fs.copyFileSync(`${__dirname}/mock-adb.sh`, path.join(dir, 'adb'));
    fs.chmodSync(path.join(dir, 'adb'), 0o700);
    const result = spawnSync('bash', [`${__dirname}/../device-info.sh`, 'USB123', 'SILENT'], {
      encoding: 'utf8', timeout: 10000, env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH } });
    assert.equal(result.status, 0, result.stderr);
    const info = deviceInfo.parseDeviceInfo(result.stdout);
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
  const info = deviceInfo.parseDeviceInfo([
    'T\tbattery_level\t71', 'T\tbattery_status\t3', 'T\tbattery_temp\t301', 'T\tandroid\t16', 'T\tsdk\t36',
    'T\tmem_kb\t11788072', 'T\tscreen\t1600x2560', 'T\tinternal\t133125120:233775104',
    'T\texternal_A\tA:usb:1048576:31457280', 'T\texternal_B\tB:usb:0:1048576', 'T\tbogus', ''].join('\n')).T;
  assert.deepEqual(plain(deviceInfo.deviceDetails(info)), [
    { label: 'Battery', value: '71 % · on battery · 30.1 °C' },
    { label: 'Android', value: '16 (SDK 36)' },
    { label: 'Internal storage', value: '136 GB of 239 GB used (57 %)' },
    { label: 'USB drive A', value: '1.1 GB of 32.2 GB used (3 %)' },
    { label: 'USB drive B', value: '0 MB of 1.1 GB used (0 %)' },
    { label: 'Memory', value: '12.1 GB' },
    { label: 'Screen', value: '1600 × 2560 · 16:10' }]);
  assert.equal(deviceInfo.batteryLabel({ level: 100, status: 5 }), '100 % · full');
  assert.equal(deviceInfo.deviceDetails({ battery: { level: 95, status: 2, plugged: ['ac'] } })[0].value, '95 % · charging (AC)');
  assert.deepEqual([999842816, 122373248, 500].map(deviceInfo.formatSize), ['1.02 TB', '125 GB', '1 MB']);
  assert.deepEqual([[1080, 2400], [1440, 3120], [1920, 1080], [1536, 2048], [1000, 999]].map(([w, h]) => deviceInfo.aspectRatio(w, h)),
    ['20:9', '19.5:9', '16:9', '4:3', '1.00:1']);
  assert.deepEqual(plain(deviceInfo.deviceDetails(null)), []);
  assert.deepEqual(plain(deviceInfo.withDeviceInfo([{ serial: 'T' }, { serial: 'X' }], { T: { android: '16' } })),
    [{ serial: 'T', info: { android: '16' } }, { serial: 'X', info: null }]);
});

