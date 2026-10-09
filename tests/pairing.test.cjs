// Pairing.js projections and qr-pair.sh against a fake qrencode.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { spawnSync } = require('node:child_process');
const pairing = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../Pairing.js`, 'utf8'), pairing);
const plain = value => JSON.parse(JSON.stringify(value));

// Runs qr-pair.sh with a PATH of only the tools it uses (so a real qrencode
// is never found) plus the fake qrencode, or without qrencode at all.
function runQrPair(withQrencode) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'droidlink qr fixture-'));
  try {
    const log = path.join(dir, 'log');
    for (const tool of ['bash', 'od', 'sed', 'cat'])
      fs.symlinkSync(spawnSync('bash', ['-c', `command -v ${tool}`], { encoding: 'utf8' }).stdout.trim(), path.join(dir, tool));
    if (withQrencode) {
      fs.copyFileSync(`${__dirname}/mock-qrencode.sh`, path.join(dir, 'qrencode'));
      fs.chmodSync(path.join(dir, 'qrencode'), 0o700);
    }
    const result = spawnSync(path.join(dir, 'bash'), [`${__dirname}/../qr-pair.sh`], {
      encoding: 'utf8', timeout: 10000, env: { PATH: dir, DROIDLINK_QR_LOG: log } });
    return { ...result, log: fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '' };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('qr-pair.sh encodes a fresh service and password, never in argv', () => {
  const first = runQrPair(true), second = runQrPair(true);
  assert.equal(first.status, 0, first.stderr);
  const code = pairing.parseQrPairing(first.stdout);
  assert.match(code.service, /^droidlink-[a-z2-9]{8}$/);
  assert.match(code.password, /^[a-z2-9]{16}$/);
  assert.deepEqual([code.size, code.cells], [3, '111101011']);
  assert.ok(first.log.includes(`payload WIFI:T:ADB;S:${code.service};P:${code.password};;`), first.log);
  assert.ok(!/^argv .*(droidlink-|WIFI:)/m.test(first.log), 'payload stays out of argv: ' + first.log);
  assert.notEqual(pairing.parseQrPairing(second.stdout).password, code.password, 'each code is new');
});

test('qr-pair.sh names the missing qrencode', () => {
  const result = runQrPair(false);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Missing qrencode/);
  assert.equal(result.stdout, '', 'no half code is printed');
});

test('parseQrPairing reads the service, password and modules', () => {
  const output = 'service\tdroidlink-abcd2345\npassword\tabcdefgh23456789\nrow\t10\r\nrow\t01\n';
  assert.deepEqual(plain(pairing.parseQrPairing(output)),
    { service: 'droidlink-abcd2345', password: 'abcdefgh23456789', size: 2, cells: '1001' });
});

test('parseQrPairing rejects incomplete or malformed output', () => {
  const service = 'service\tdroidlink-abcd2345\n', password = 'password\tabcdefgh23456789\n';
  for (const output of ['', service + 'row\t1\n', password + 'row\t1\n', service + password,
    service + password + 'row\t10\nrow\t1\n', service + 'password\tshort\nrow\t1\n', 'service\tother-abcd2345\n' + password + 'row\t1\n'])
    assert.throws(() => pairing.parseQrPairing(output), /expected service, password and square/, JSON.stringify(output));
});

test('validPairingSecret takes six digits or a QR password', () => {
  for (const secret of ['123456', 'abcdefgh23456789'])
    assert.equal(pairing.validPairingSecret(secret), true, secret);
  for (const secret of ['', '12345', '1234567', 'abcdefgh2345678', 'ABCDEFGH23456789', 'abcdefgh2345678;', null])
    assert.equal(pairing.validPairingSecret(secret), false, String(secret));
});

test('qrPairingEndpoint matches only the scanned code\'s pairing service', () => {
  const rows = [
    { pair: true, serial: 'adb-OTHER-pair', endpoint: '192.168.1.9:40000' },
    { pair: false, serial: 'droidlink-abcd2345', endpoint: '192.168.1.5:37000' },
    { pair: true, serial: 'droidlink-abcd2345', endpoint: '192.168.1.5:42000' }];
  assert.equal(pairing.qrPairingEndpoint(rows, 'droidlink-abcd2345'), '192.168.1.5:42000');
  assert.equal(pairing.qrPairingEndpoint(rows, 'droidlink-zzzz2345'), '');
  assert.equal(pairing.qrPairingEndpoint(rows, ''), '');
  assert.equal(pairing.qrPairingEndpoint(null, 'droidlink-abcd2345'), '');
});
