// Webcam.js projections. tests/mirror-session.test.cjs runs the QML that uses them.
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const webcamModel = loadJs('Webcam.js');
const plain = value => JSON.parse(JSON.stringify(value));

const cameraList = readFileSync(`${__dirname}/camera-sizes.txt`, 'utf8');
const webcam = overrides => Object.assign(plain(webcamModel.webcamSettings('')), overrides);

test('camera list is parsed per camera, without high-speed sizes', () => {
  const cameras = plain(webcamModel.parseCameraList(cameraList));
  assert.deepEqual(cameras.map(c => [c.id, c.facing, c.sensor]), [['0', 'back', '4128x3096'], ['1', 'front', '2032x1524'], ['2', 'front', '4000x3000']]);
  assert.deepEqual(cameras[1].fps, [10, 15, 20, 24, 30]);
  assert.deepEqual(cameras[1].zoom, [1, 8]);
  assert.equal(cameras[1].sizes[0], '2032x1524');
  assert.ok(cameras[2].sizes.includes('3840x2160'));
  const fast = plain(webcamModel.parseCameraList('--camera-id=0    (back, 1920x1080, fps=[15, 30])\n  - 1920x1080\n  High speed capture (--camera-high-speed):\n    - 1280x720 (fps=[120, 240])\n'));
  assert.deepEqual(fast[0].sizes, ['1920x1080']);
  assert.equal(fast[0].zoom, null);
  assert.deepEqual(plain(webcamModel.parseCameraList('ERROR: Could not find any ADB device')), []);
});

test('camera, size, fps and zoom choices come from the listed camera', () => {
  const cameras = webcamModel.parseCameraList(cameraList);
  assert.deepEqual(plain(webcamModel.cameraOptions(cameras)).map(o => o.label), ['Back · 4128×3096 · camera 0', 'Front · 2032×1524 · camera 1', 'Front · 4000×3000 · camera 2']);
  assert.deepEqual(plain(webcamModel.cameraOptions([])).map(o => o.value), ['front', 'back']);
  assert.equal(webcamModel.chosenCamera(cameras, 'front').id, '1');
  assert.equal(webcamModel.chosenCamera(cameras, 'id:2').id, '2');
  const sizes = plain(webcamModel.cameraSizeOptions(webcamModel.chosenCamera(cameras, 'id:2')));
  assert.equal(sizes[0].value, 'auto');
  assert.equal(sizes[1].label, '4000×3000 · 4:3');
  assert.ok(sizes.some(o => o.label === '3840×2160 · 16:9 · 4K'));
  assert.ok(!sizes.some(o => o.value === '352x288'));
  assert.deepEqual(plain(webcamModel.cameraFpsOptions(cameras[0])).map(o => o.value), ['30', '24', '20', '15', '10']);
  assert.deepEqual(plain(webcamModel.cameraZoomOptions(cameras[0])).map(o => o.value), ['1', '1.5', '2', '3', '4', '6', '8']);
  assert.deepEqual(plain(webcamModel.cameraZoomOptions(null)).map(o => o.value), ['1']);
});

test('presets pick the closest size and rate the camera supports', () => {
  const cameras = webcamModel.parseCameraList(cameraList);
  assert.equal(webcamModel.pickCameraSize(cameras[2], '3840x2160'), '3840x2160');
  assert.equal(webcamModel.pickCameraSize(cameras[1], '3840x2160'), '2032x1144');
  assert.equal(webcamModel.pickCameraSize(cameras[1], '1920x1080'), '1920x1080');
  assert.equal(webcamModel.pickCameraSize(null, '1280x720'), '1280x720');
  // No size of the target's aspect: scrcpy chooses, never an unlisted size.
  assert.equal(webcamModel.pickCameraSize({ sizes: ['1440x1080', '640x480'] }, '1920x1080'), 'auto');
  assert.equal(webcamModel.pickCameraFps({ fps: [5, 8] }, '30'), '8');
  assert.deepEqual(plain(webcamModel.cameraFpsOptions({ fps: [5, 8] })).map(o => o.value), ['8', '5']);
  assert.equal(webcamModel.pickCameraFps(cameras[1], '24'), '24');
  assert.equal(webcamModel.pickCameraFps({ fps: [15, 30] }, '24'), '15');
  assert.deepEqual(plain(webcamModel.webcamPresets()).map(p => p.value), ['call', 'sharp', 'saver']);
});

test('webcam summary names what the folded settings are', () => {
  assert.equal(webcamModel.webcamSummary(webcam()), '1080p · 30 fps · 12 Mbps · H.265');
  assert.equal(webcamModel.webcamSummary(webcam({ size: '2032x1144', orientation: 'flip0', zoom: '2', torch: true, buffer: '100' })), '2032×1144 · 30 fps · 12 Mbps · H.265 · Mirror · 2× · Torch · 100 ms');
  assert.equal(webcamModel.webcamSummary(webcam({ size: 'auto', codec: 'h264' })), 'Auto size · 30 fps · 12 Mbps · H.264');
});

test('webcam settings fall back to defaults for missing or mistyped values', () => {
  assert.deepEqual(plain(webcamModel.webcamSettings('{"camera":"id:2","torch":true,"fps":30,"bogus":1}')), webcam({ camera: 'id:2', torch: true }));
  assert.equal(webcamModel.webcamSettings('not json').preset, 'call');
});

test('webcam command validates camera options and adds only non-default adjustments', () => {
  assert.deepEqual(plain(webcamModel.webcamCommand('USB123', webcam({ camera: 'front', orientation: 'flip90', size: 'auto', fps: '30', bitRate: '8', codec: 'h264' }), '/dev/video12')), [
    'scrcpy', '--serial=USB123', '--video-source=camera', '--camera-facing=front',
    '--capture-orientation=flip90', '--no-audio', '--no-window', '--v4l2-sink=/dev/video12',
    '--camera-fps=30', '--video-bit-rate=8M', '--video-codec=h264']);
  const tuned = plain(webcamModel.webcamCommand('USB123', webcam({ camera: 'id:2', size: '3840x2160', zoom: '2', torch: true, buffer: '100' }), '/dev/video4'));
  assert.ok(tuned.includes('--camera-id=2') && !tuned.some(a => a.startsWith('--camera-facing')));
  for (const arg of ['--camera-size=3840x2160', '--camera-zoom=2', '--camera-torch', '--v4l2-buffer=100', '--video-bit-rate=12M', '--video-codec=h265'])
    assert.ok(tuned.includes(arg), arg);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ camera: 'side' }), '/dev/video4'), /Invalid camera/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ camera: 'id:1;rm' }), '/dev/video4'), /Invalid camera/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ orientation: '45' }), '/dev/video4'), /orientation/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ size: '1080p' }), '/dev/video4'), /camera size/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ fps: '0' }), '/dev/video4'), /frame rate/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ bitRate: '500' }), '/dev/video4'), /bitrate/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ codec: 'mpeg2' }), '/dev/video4'), /codec/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ zoom: '0' }), '/dev/video4'), /zoom/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam({ buffer: '-5' }), '/dev/video4'), /buffer/);
  assert.throws(() => webcamModel.webcamCommand('USB123', webcam(), '/dev/video4;echo'), /webcam output/);
});

test('webcam setup gives short actions and copyable Omarchy commands', () => {
  const missing = webcamModel.webcamSetup('missing-package');
  assert.equal(missing.title, 'Virtual camera driver missing');
  assert.equal(missing.step, 'install');
  assert.equal(missing.commands, 'omarchy pkg add v4l2loopback-dkms\nsudo modprobe v4l2loopback devices=1 exclusive_caps=1\n'
    + "printf 'v4l2loopback\\n' | sudo tee /etc/modules-load.d/v4l2loopback.conf\n"
    + "printf 'options v4l2loopback devices=1 exclusive_caps=1\\n' | sudo tee /etc/modprobe.d/v4l2loopback.conf");
  assert.equal(webcamModel.webcamSetup('module-not-loaded').step, 'load');
  assert.equal(webcamModel.webcamSetup('module-unavailable').step, '');
});
