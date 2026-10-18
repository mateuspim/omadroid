// SettingsFile.js: the omadroid.ini URL every Core.Settings is built with.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const settingsFile = loadJs('SettingsFile.js');

test('omadroidIniUrl uses XDG_CONFIG_HOME, else ~/.config, and is never empty', () => {
  assert.equal(settingsFile.omadroidIniUrl('/x/conf', '/home/me'), 'file:///x/conf/omarchy/omadroid.ini');
  assert.equal(settingsFile.omadroidIniUrl('', '/home/me'), 'file:///home/me/.config/omarchy/omadroid.ini');
  assert.equal(settingsFile.omadroidIniUrl('', '/home/a b'), 'file:///home/a%20b/.config/omarchy/omadroid.ini');
});
