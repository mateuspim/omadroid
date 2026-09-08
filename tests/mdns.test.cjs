// Offline only: every avahi-browse invocation resolves to a temporary fixture.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const vm = require('node:vm');
const repo = path.resolve(__dirname, '..');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(repo, 'Model.js'), 'utf8'), model);

for (const scenario of ['', 'avahi_unavailable', 'partial', 'timeout']) {
  test(`mDNS shell helper: ${scenario || 'resolved services'} (fake Avahi only)`, () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'droidlink mdns fixture-'));
    try {
      const fake = path.join(dir, 'avahi-browse');
      fs.copyFileSync(path.join(__dirname, 'mock-avahi-browse.sh'), fake);
      fs.chmodSync(fake, 0o700);
      const result = spawnSync('bash', [path.join(repo, 'discover-mdns.sh')], {
        encoding: 'utf8', timeout: 12000,
        env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH,
          TMPDIR: dir, DROIDLINK_TEST_CASE: scenario }
      });
      assert.ifError(result.error);
      assert.equal(result.status, scenario ? 1 : 0, result.stderr);
      const rows = model.parseMdns(result.stdout);
      assert.equal(rows.length, scenario === 'avahi_unavailable' ? 0 : scenario === 'partial' ? 2 : 3);
      assert.equal(rows.some(row => row.serial === 'removed'), false);
      if (scenario === 'avahi_unavailable') assert.match(result.stderr, /Daemon not running/);
      if (scenario === 'timeout') assert.match(result.stderr, /timed out/);
      if (scenario === 'partial') assert.match(result.stderr, /Pairing resolver failed/);
      assert.deepEqual(fs.readdirSync(dir), ['avahi-browse'], 'temporary scan files cleaned up');
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
}
