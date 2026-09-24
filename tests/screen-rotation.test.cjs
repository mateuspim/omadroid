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
    sessionActive: true, sessionPid: 7312, deviceSerial: 'USB123', controlBusy: false,
    selectedRotation: -1, requestedRotation: -1, requestedPid: 0, requestedSerial: '',
    pendingAutoRotate: false, controlMessage: '', controlFailed: false,
    ScreenRotation: screenRotationModel,
    setRotation: new FakeCommand(), freeRotation: new FakeCommand(),
  });
  context.root = context;
  loadQmlMethods(controlsSource, context);
  return context;
}

test('orientation commands lock each Android rotation and free restores auto-rotate', () => {
  for (const rotation of [0, 1, 2, 3]) {
    assert.deepEqual(Array.from(screenRotationModel.orientationCommand('USB123', rotation)),
      ['adb', '-s', 'USB123', 'shell', 'wm', 'user-rotation', 'lock', String(rotation)]);
  }
  assert.deepEqual(Array.from(screenRotationModel.autoRotateCommand('USB123')),
    ['adb', '-s', 'USB123', 'shell', 'wm', 'user-rotation', 'free']);
});

test('invalid serials or rotations cannot become ADB commands', () => {
  for (const serial of ['', 'USB\n123', 'USB\u0000'])
    assert.throws(() => screenRotationModel.orientationCommand(serial, 0), /authorized Android device/);
  for (const rotation of [-1, 4, 1.5, '1'])
    assert.throws(() => screenRotationModel.orientationCommand('USB123', rotation), /expected a value from 0 to 3/);
  assert.throws(() => screenRotationModel.autoRotateCommand('USB\n123'), /authorized Android device/);
});

test('orientation command errors are reported instead of treated as success', () => {
  assert.equal(screenRotationModel.orientationFailure(0, '', '', 'lock Portrait'), '');
  for (const [code, output, error] of [[0, 'Error: unknown command', ''], [1, '', 'permission denied'], [127, '', 'missing adb']]) {
    assert.match(screenRotationModel.orientationFailure(code, output, error, 'lock Portrait'), /Could not lock Portrait/);
  }
});

test('orientation requests are disabled without an active device session or during a request', () => {
  for (const override of [{ sessionActive: false }, { deviceSerial: '' }, { controlBusy: true }]) {
    const controls = Object.assign(rotationControlsFixture(), override);
    controls.requestRotation(0);
    controls.requestAutoRotate();
    assert.equal(controls.setRotation.calls.length, 0);
    assert.equal(controls.freeRotation.calls.length, 0);
  }
});

test('locking an orientation targets the selected serial and marks the choice', () => {
  const controls = rotationControlsFixture();
  controls.requestRotation(3);
  assert.deepEqual(controls.setRotation.calls[0], {
    argv: ['adb', '-s', 'USB123', 'shell', 'wm', 'user-rotation', 'lock', '3'], seconds: 5
  });
  controls.finishRotation(0, '', '');
  assert.equal(controls.selectedRotation, 3);
  assert.equal(controls.controlFailed, false);
  assert.match(controls.controlMessage, /Landscape \(left\) locked/);
});

test('auto-rotate reset frees the device lock and ignores stale completions', () => {
  const controls = rotationControlsFixture();
  controls.requestAutoRotate();
  assert.deepEqual(controls.freeRotation.calls[0], {
    argv: ['adb', '-s', 'USB123', 'shell', 'wm', 'user-rotation', 'free'], seconds: 5
  });
  controls.sessionPid = 8421;
  controls.finishRotation(0, '', '');
  assert.notEqual(controls.controlMessage, 'Auto-rotate enabled.');
  controls.sessionPid = 7312;
  controls.requestAutoRotate();
  controls.finishRotation(0, '', '');
  assert.equal(controls.selectedRotation, -1);
  assert.equal(controls.controlMessage, 'Auto-rotate enabled.');
});
