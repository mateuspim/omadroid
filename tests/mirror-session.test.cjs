// Execute MirrorSession's and WebcamOptions' QML methods with named fakes:
// launch arguments, the webcam Apply restart and the camera fit run without
// a shell, a device or scrcpy.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const Model = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Model.js`, 'utf8'), Model);
const sessionSource = readFileSync(`${__dirname}/../MirrorSession.qml`, 'utf8');
const webcamSource = readFileSync(`${__dirname}/../WebcamOptions.qml`, 'utf8');
const cameraList = readFileSync(`${__dirname}/camera-sizes.txt`, 'utf8');

class FakeSessionCommand {
  busy = false;
  calls = [];
  /** Capture argv instead of running it. @param {string[]} argv @param {number} seconds */
  start(argv, seconds) {
    this.calls.push(Array.from(argv));
    return true;
  }
}

class FakeQt {
  later = [];
  /** Queue instead of deferring, so a test runs the queue when it chooses. */
  callLater(fn) {
    this.later.push(fn);
  }
}

/** Load production QML methods into a JS context. @param {string} source @param {vm.Context} context */
function loadQmlMethods(source, context) {
  for (const declaration of source.match(/^  function [\s\S]*?^  }/gm) || [])
    vm.runInContext(declaration, context);
}

/** An idle session. Example: sessionFixture({ wakeOnLaunch: true }).launchMirror(...). */
function sessionFixture(overrides) {
  const context = vm.createContext(Object.assign({
    Model, Qt: new FakeQt(), Math, Date, Object, String, Number, JSON,
    missingTools: '', wakeOnLaunch: false, unlockOnLaunch: false,
    busy: false, stopping: false, message: '', failed: false,
    sessionSerial: '', sessionType: 'mirror', sessionAudioOnly: false, sessionRecording: '', sessionSink: '',
    sessionPid: 0, sessionArgs: [], restartPending: false, restartTarget: null, webcamReportDue: false,
    powerWarning: '', pendingLaunch: [], sessionScript: '/plugin/session.sh', powerScript: '/plugin/device-power.sh',
    launcher: new FakeSessionCommand(), preparer: new FakeSessionCommand(), stopper: new FakeSessionCommand()
  }, overrides));
  loadQmlMethods(sessionSource, context);
  return context;
}

test('launchMirror starts scrcpy on the given serial, through wake when asked', () => {
  const plain = sessionFixture();
  plain.launchMirror('USB123', Model.builtInProfiles()[0], '', false);
  const argv = plain.launcher.calls[0];
  assert.deepEqual(argv.slice(0, 6), ['bash', '/plugin/session.sh', 'launch', 'USB123', 'mirror', '']);
  assert.equal(plain.sessionSerial, 'USB123');
  const waking = sessionFixture({ wakeOnLaunch: true });
  waking.launchMirror('PHONE', Model.builtInProfiles()[0], '', true);
  assert.deepEqual(waking.preparer.calls[0].slice(-4), ['connected', '1', '0', 'PHONE']);
  assert.equal(waking.sessionType, 'audio');
});

test('launches are refused with the missing tools named, and ignored while busy', () => {
  const missing = sessionFixture({ missingTools: 'scrcpy' });
  missing.launchMirror('USB123', Model.builtInProfiles()[0], '', false);
  assert.equal(missing.failed, true);
  assert.match(missing.message, /Install scrcpy/);
  const busy = sessionFixture({ busy: true });
  busy.launchWebcam('USB123', Model.webcamSettings(''), '/dev/video12');
  assert.equal(busy.launcher.calls.length, 0);
  const noSink = sessionFixture();
  noSink.launchWebcam('USB123', Model.webcamSettings(''), '');
  assert.match(noSink.message, /No v4l2loopback output/);
});

test('Apply stops the webcam, then restarts it on the same phone and output with the new settings', () => {
  const session = sessionFixture({ busy: true, sessionType: 'webcam', sessionPid: 42, sessionSerial: 'USB123', sessionSink: '/dev/video12' });
  const settings = Object.assign(Model.webcamSettings(''), { fps: '24' });
  session.restartWebcam(settings);
  assert.equal(session.restartPending, true);
  assert.deepEqual(session.stopper.calls[0], ['bash', '/plugin/session.sh', 'stop']);
  session.applyEnded(['inactive'], true);
  assert.equal(session.restartPending, false);
  session.Qt.later.forEach(fn => fn());
  const argv = session.launcher.calls[0];
  assert.deepEqual(argv.slice(0, 2), ['env', 'OMADROID_KEEP_READERS=1']);
  assert.ok(argv.includes('--camera-fps=24') && argv.includes('--v4l2-sink=/dev/video12'), JSON.stringify(argv));
});

test('a webcam that failed before any status saw it reports its error once', () => {
  const session = sessionFixture({ sessionType: 'webcam', webcamReportDue: true });
  session.applyEnded(['inactive', 'Camera 7 not found'], false);
  assert.equal(session.failed, true);
  assert.equal(session.message, 'Camera 7 not found');
  session.report('', false);
  session.applyEnded(['inactive', 'Camera 7 not found'], false);
  assert.equal(session.message, '', 'old errors are not repeated');
});

test('cameraFitChanges swaps a facing for a camera id and an unlisted size for the closest', () => {
  const context = vm.createContext({ Model, webcam: Object.assign(Model.webcamSettings(''), { camera: 'front', size: '9999x9999' }) });
  loadQmlMethods(webcamSource, context);
  const cameras = Model.parseCameraList(cameraList);
  const camera = Model.chosenCamera(cameras, 'front');
  const changes = context.cameraFitChanges(camera);
  assert.equal(changes.camera, 'id:' + camera.id);
  assert.ok(camera.sizes.includes(changes.size), changes.size);
});
