// Execute the production command builder and QML method bodies with named fakes.
// This suite never dispatches keys, launches a window, or contacts a device.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const screenPowerModel = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../ScreenPower.js`, 'utf8'), screenPowerModel);
const controlsSource = readFileSync(`${__dirname}/../ScreenPowerControls.qml`, 'utf8');
const paneSource = readFileSync(`${__dirname}/../MirrorOptions.qml`, 'utf8');

class FakeScreenCommand {
  calls = [];
  /** Capture argv without invoking the compositor. @param {string[]} argv @param {number} seconds @returns {boolean} */
  start(argv, seconds) {
    this.calls.push({ argv: Array.from(argv), seconds });
    return true;
  }
}

class FakeReleaseTimer {
  restarts = 0;
  /** Record scheduling without waiting. @returns {void} */
  restart() {
    this.restarts++;
  }
}

/** Load production QML methods into a JS context without initializing a shell.
 * @param {string} qmlSource @param {vm.Context} context @returns {void}
 */
function loadQmlMethods(qmlSource, context) {
  const declarations = qmlSource.match(/^  function [\s\S]*?^  }/gm) || [];
  for (const declaration of declarations) {
    const javascript = declaration.replace(/: (?:bool|int|string|void)\b/g, '');
    vm.runInContext(javascript, context);
  }
}

/** Compose isolated collaborators. Example: screenControlsFixture().requestScreenPower(true).
 * @returns {vm.Context}
 */
function screenControlsFixture() {
  const context = vm.createContext({
    sessionPid: 7312, sessionActive: true, controlBusy: false,
    requestedPid: 0, requestedScreenOn: false, pressFailure: '',
    controlMessage: '', controlFailed: false, ScreenPower: screenPowerModel,
    keyPress: new FakeScreenCommand(), keyRelease: new FakeScreenCommand(),
    releaseDelay: new FakeReleaseTimer(),
  });
  context.root = context;
  loadQmlMethods(controlsSource, context);
  return context;
}

test('screen power targets the owned scrcpy PID with paired keys and no focus change', () => {
  for (const screenOn of [true, false]) {
    const modifiers = screenOn ? 'ALT + SHIFT' : 'ALT';
    for (const pressed of [true, false]) {
      const argv = Array.from(screenPowerModel.screenPowerKeyCommand(7312, screenOn, pressed));
      assert.deepEqual(argv.slice(0, 2), ['hyprctl', 'dispatch']);
      assert.equal(argv[2], `hl.dsp.send_key_state({mods="${modifiers}",key="O",state="${pressed ? 'down' : 'up'}",window="pid:7312"})`);
    }
  }
});

test('invalid PIDs or states cannot become compositor commands', () => {
  for (const invalidPid of [0, -1, 0.5, NaN, Infinity, '7312', '1"}); os.execute("id")']) {
    assert.throws(() => screenPowerModel.screenPowerKeyCommand(invalidPid, true, true), /expected a positive integer/);
  }
  assert.throws(() => screenPowerModel.screenPowerKeyCommand(7312, 'on', true), /expected two booleans/);
  assert.throws(() => screenPowerModel.screenPowerKeyCommand(7312, true, 'down'), /expected two booleans/);
});

test('errors cannot be mistaken for a successful phone power change', () => {
  assert.equal(screenPowerModel.screenPowerFailure(0, 'ok\n', ''), '');
  for (const [code, output, error] of [[0, 'window not found', ''], [0, '', ''], [1, 'ok', ''], [127, '', 'missing hyprctl']]) {
    assert.match(screenPowerModel.screenPowerFailure(code, output, error), /Screen control failed/);
  }
});

test('requests are disabled after stop, without a PID, or during an earlier request', () => {
  for (const override of [{ sessionActive: false }, { sessionPid: 0 }, { controlBusy: true }]) {
    const controls = Object.assign(screenControlsFixture(), override);
    controls.requestScreenPower(true);
    assert.equal(controls.keyPress.calls.length, 0);
  }
});

test('a screen request preserves the original target through key release', () => {
  const controls = screenControlsFixture();
  controls.requestScreenPower(true);
  assert.match(controls.keyPress.calls[0].argv[2], /ALT \+ SHIFT.*down.*pid:7312/);
  assert.equal(controls.keyPress.calls[0].seconds, 3);
  controls.finishPowerPress(0, 'ok\n', '');
  assert.equal(controls.releaseDelay.restarts, 1);
  controls.sessionPid = 8421;
  vm.runInContext(controlsSource.match(/onTriggered: (keyRelease.start[^\n]+)/)[1], controls);
  assert.match(controls.keyRelease.calls[0].argv[2], /up.*pid:7312/);
  controls.controlMessage = '';
  controls.finishPowerRelease(0, 'ok\n', '');
  assert.equal(controls.controlMessage, '', 'old completion cannot update a new session');
});

test('ambiguous press failures still release the shortcut and report the failure', () => {
  const controls = screenControlsFixture();
  controls.requestScreenPower(false);
  controls.finishPowerPress(124, '', 'timed out');
  assert.equal(controls.releaseDelay.restarts, 1);
  controls.finishPowerRelease(0, 'ok\n', '');
  assert.equal(controls.controlFailed, true);
  assert.match(controls.controlMessage, /timed out/);
});

test('success acknowledges dispatch without claiming to observe Android display state', () => {
  const controls = screenControlsFixture();
  controls.requestScreenPower(true);
  controls.finishPowerRelease(0, 'ok\n', '');
  assert.equal(controls.controlFailed, false);
  assert.match(controls.controlMessage, /request sent.*authentication/);
  controls.requestScreenPower(false);
  controls.finishPowerRelease(0, 'ok\n', '');
  assert.match(controls.controlMessage, /Mirroring continues/);
  controls.finishPowerRelease(1, '', 'release failed');
  assert.equal(controls.controlFailed, true);
});

test('enabling screen-off opts into idle prevention but allows a later explicit opt-out', () => {
  const context = vm.createContext({ profile: { screenOff: false, keepActive: false }, profileName: 'Balanced' });
  loadQmlMethods(paneSource, context);
  context.changeOption('screenOff', true);
  assert.equal(context.profile.keepActive, true);
  assert.equal(context.profileName, 'Custom');
  context.changeOption('keepActive', false);
  assert.equal(context.profile.keepActive, false);
  assert.equal(context.profile.screenOff, true);
});
