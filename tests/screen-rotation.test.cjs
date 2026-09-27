// Execute the production ADB command builders and QML method bodies with fakes.
// This suite never changes a device or contacts the compositor.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const screenRotationModel = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../ScreenRotation.js', 'utf8'), screenRotationModel);
const controlsSource = readFileSync(__dirname + '/../ScreenRotationControls.qml', 'utf8');

class FakeCommand {
  calls = [];
  start(argv, seconds) {
    this.calls.push({ argv: Array.from(argv), seconds });
    return true;
  }
}

function loadQmlMethods(qmlSource, context) {
  const declarations = qmlSource.match(/^  function [\s\S]*?^  }/gm) || [];
  for (const declaration of declarations) {
    const javascript = declaration.replace(/: (?:bool|int|string|void)\b/g, '');
    vm.runInContext(javascript, context);
  }
}

function rotationControlsFixture() {
  const context = vm.createContext({
    sessionActive: true, sessionPid: 7312, deviceSerial: 'USB123', sessionScript: SCRIPT, controlBusy: false,
    selectedRotation: -1, rotationKnown: false, requestedRotation: -1, requestedPid: 0, requestedSerial: '',
    pendingAutoRotate: false, queriedPid: 0, controlMessage: '', controlFailed: false,
    ScreenRotation: screenRotationModel,
    setRotation: new FakeCommand(), freeRotation: new FakeCommand(), readRotation: new FakeCommand(),
  });
  context.root = context;
  loadQmlMethods(controlsSource, context);
  return context;
}

const SCRIPT = '/plugins/droidlink/session.sh';

test('rotation commands go through the session helper, which owns the device serial', () => {
  for (const rotation of [0, 1, 2, 3]) {
    assert.deepEqual(Array.from(screenRotationModel.orientationCommand(SCRIPT, rotation)),
      ['bash', SCRIPT, 'rotate', 'lock', String(rotation)]);
  }
  assert.deepEqual(Array.from(screenRotationModel.autoRotateCommand(SCRIPT)), ['bash', SCRIPT, 'rotate', 'free']);
  assert.deepEqual(Array.from(screenRotationModel.rotationQueryCommand(SCRIPT)), ['bash', SCRIPT, 'rotate', 'query']);
});

test('invalid helper paths or rotations cannot become commands', () => {
  for (const script of ['', '/tmp/x\nrm', '/tmp/\u0000'])
    assert.throws(() => screenRotationModel.orientationCommand(script, 0), /Invalid session helper path/);
  for (const rotation of [-1, 4, 1.5, '1'])
    assert.throws(() => screenRotationModel.orientationCommand(SCRIPT, rotation), /expected a value from 0 to 3/);
  assert.throws(() => screenRotationModel.autoRotateCommand(''), /Invalid session helper path/);
  assert.throws(() => screenRotationModel.rotationQueryCommand(''), /Invalid session helper path/);
});

test('rotation query output parses into auto-rotate, owned and phone-set locks', () => {
  assert.deepEqual({ ...screenRotationModel.parseRotationState('free\n') }, { rotation: -1, owned: false });
  assert.deepEqual({ ...screenRotationModel.parseRotationState('lock 2\n') }, { rotation: 2, owned: false });
  assert.deepEqual({ ...screenRotationModel.parseRotationState('lock 1\nowned\n') }, { rotation: 1, owned: true });
  for (const text of ['', 'lock 4', 'locked 1', 'Error: device offline'])
    assert.throws(() => screenRotationModel.parseRotationState(text), /Unexpected rotation state/);
});

test('status messages say whether the lock is released when the session stops', () => {
  assert.equal(screenRotationModel.rotationStateMessage(-1, false), 'Auto-rotate enabled.');
  assert.match(screenRotationModel.rotationStateMessage(1, true), /Landscape \(right\) locked\. Released when the session stops/);
  assert.match(screenRotationModel.rotationStateMessage(2, false), /Portrait inverted locked on the phone\. Kept after/);
});

test('only a non-zero helper exit is a failure, reported with its diagnostic', () => {
  assert.equal(screenRotationModel.orientationFailure(0, 'lock 1', '', 'lock Portrait'), '');
  assert.match(screenRotationModel.orientationFailure(1, '', 'Error: unknown command', 'lock Portrait'),
    /Could not lock Portrait \(exit 1\): Error: unknown command/);
  assert.match(screenRotationModel.orientationFailure(124, '', '', 'lock Portrait'), /adb returned no diagnostic/);
});

test('orientation requests are disabled without an active device session or during a request', () => {
  for (const override of [{ sessionActive: false }, { deviceSerial: '' }, { controlBusy: true }]) {
    const controls = Object.assign(rotationControlsFixture(), override);
    controls.requestRotation(0);
    controls.requestAutoRotate();
    controls.queryRotation();
    assert.equal(controls.setRotation.calls.length, 0);
    assert.equal(controls.freeRotation.calls.length, 0);
    assert.equal(controls.readRotation.calls.length, 0);
  }
});

test('locking an orientation marks the choice and says it is released on stop', () => {
  const controls = rotationControlsFixture();
  controls.requestRotation(3);
  assert.deepEqual(controls.setRotation.calls[0], { argv: ['bash', SCRIPT, 'rotate', 'lock', '3'], seconds: 6 });
  controls.finishRotation(0, '', '');
  assert.equal(controls.selectedRotation, 3);
  assert.equal(controls.rotationKnown, true);
  assert.equal(controls.controlFailed, false);
  assert.match(controls.controlMessage, /Landscape \(left\) locked\. Released when the session stops/);
});

test('auto-rotate reset frees the device lock and ignores stale completions', () => {
  const controls = rotationControlsFixture();
  controls.requestAutoRotate();
  assert.deepEqual(controls.freeRotation.calls[0], { argv: ['bash', SCRIPT, 'rotate', 'free'], seconds: 6 });
  controls.sessionPid = 8421;
  controls.finishRotation(0, '', '');
  assert.notEqual(controls.controlMessage, 'Auto-rotate enabled.');
  controls.sessionPid = 7312;
  controls.requestAutoRotate();
  controls.finishRotation(0, '', '');
  assert.equal(controls.selectedRotation, -1);
  assert.equal(controls.rotationKnown, true);
  assert.equal(controls.controlMessage, 'Auto-rotate enabled.');
});

test('a reloaded controls instance shows the lock read from the device', () => {
  const controls = rotationControlsFixture();
  controls.queryRotation();
  assert.deepEqual(controls.readRotation.calls[0], { argv: ['bash', SCRIPT, 'rotate', 'query'], seconds: 6 });
  controls.finishQuery(0, 'lock 2\n', '');
  assert.equal(controls.selectedRotation, 2);
  assert.equal(controls.rotationKnown, true);
  assert.match(controls.controlMessage, /locked on the phone\. Kept after the session stops/);
});

test('a query that fails or returns garbage is reported and leaves the state unknown', () => {
  for (const [code, output, error, pattern] of [[1, '', 'device offline', /Could not read the device rotation/], [0, 'nonsense', '', /Unexpected rotation state/]]) {
    const controls = rotationControlsFixture();
    controls.queryRotation();
    controls.finishQuery(code, output, error);
    assert.equal(controls.rotationKnown, false);
    assert.equal(controls.controlFailed, true);
    assert.match(controls.controlMessage, pattern);
  }
});

test('a query overtaken by a lock request or a new session is discarded', () => {
  const controls = rotationControlsFixture();
  controls.queryRotation();
  controls.requestRotation(1);
  controls.finishRotation(0, '', '');
  controls.finishQuery(0, 'free\n', '');
  assert.equal(controls.selectedRotation, 1);

  const reloaded = rotationControlsFixture();
  reloaded.queryRotation();
  reloaded.sessionPid = 9000;
  reloaded.finishQuery(0, 'lock 0\n', '');
  assert.equal(reloaded.rotationKnown, false);
});
