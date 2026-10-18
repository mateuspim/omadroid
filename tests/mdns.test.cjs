// Offline only: every avahi-browse invocation resolves to a temporary fixture.
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const repo = path.resolve(__dirname, '..');
const model = loadJs('Model.js');

// Runs the follow helper against the fake Avahi; stops it with `signal` after
// `settleMs` unless it exits on its own first.
function follow(scenario, settleMs, signal = 'SIGTERM') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omadroid mdns fixture-'));
  const fake = path.join(dir, 'avahi-browse');
  fs.copyFileSync(path.join(__dirname, 'mock-avahi-browse.sh'), fake);
  fs.chmodSync(fake, 0o700);
  const helper = spawn('bash', [path.join(repo, 'discover-mdns.sh')], {
    env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH, OMADROID_TEST_CASE: scenario }
  });
  let stdout = '', stderr = '';
  helper.stdout.on('data', chunk => stdout += chunk);
  helper.stderr.on('data', chunk => stderr += chunk);
  const stopper = setTimeout(() => helper.kill(signal), settleMs);
  return new Promise(resolve => helper.on('exit', (code, exitSignal) => {
    clearTimeout(stopper);
    // Give parent-death signals a moment to land before callers look.
    setTimeout(() => {
      resolve({ code, signal: exitSignal, stdout, stderr, dir, left: browsersLeft(dir) });
      fs.rmSync(dir, { recursive: true, force: true });
    }, 200);
  }));
}

function browsersLeft(dir) {
  return spawnSync('pgrep', ['-f', dir], { encoding: 'utf8' }).stdout.trim();
}

test('mDNS follow helper streams resolved and removed records until stopped', async () => {
  const result = await follow('', 800);
  assert.equal(result.code, 143, result.stderr);
  const records = {};
  result.stdout.split('\n').forEach(line => model.applyMdnsLine(records, line));
  const rows = model.parseMdns(Object.values(records).join('\n'));
  assert.equal(rows.length, 3);
  assert.equal(rows.some(row => row.serial === 'removed'), false);
  assert.equal(rows.find(row => row.serial === 'adb-PHONE-random').model, 'SM-X730');
  assert.equal(result.left, '', 'no browser outlives the helper');
});

test('mDNS browsers stop when the helper is killed without running its trap', async () => {
  const result = await follow('', 800, 'SIGKILL');
  assert.equal(result.signal, 'SIGKILL');
  assert.equal(result.left, '', 'a quitting shell SIGKILLs the helper; its browsers must not be orphaned');
});

for (const scenario of ['avahi_unavailable', 'partial']) {
  test(`mDNS follow helper stops when a browser exits: ${scenario}`, async () => {
    const result = await follow(scenario, 5000);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /OmaDroid mDNS: discovery stopped \(\S+ exited with 1\)/);
    if (scenario === 'avahi_unavailable') assert.match(result.stderr, /Daemon not running/);
    if (scenario === 'partial') assert.match(result.stderr, /Pairing resolver failed/);
    assert.equal(model.mdnsStatus(result.code, result.stderr, [], {}).level, 'error');
    assert.equal(result.left, '', 'no browser outlives the helper');
  });
}
