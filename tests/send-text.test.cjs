// SendText.js projections. tests/send-text.sh covers send-text.sh itself.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadJs } = require('./load-js.cjs');
const sendText = loadJs('SendText.js');
const plain = (value) => JSON.parse(JSON.stringify(value));
const devices = [
  { serial: 'A', status: 'device' },
  { serial: 'OFF', status: 'offline' },
  { serial: 'B', status: 'device' },
  { serial: 'C', status: 'device' },
];

test('unsupportedChars lists characters outside printable ASCII once', () => {
  assert.deepEqual(plain(sendText.unsupportedChars('hello ~!')), []);
  assert.deepEqual(plain(sendText.unsupportedChars('café crème')), ['é', 'è']);
  assert.deepEqual(plain(sendText.unsupportedChars('a\tb\nc\x7f😀')), ['\t', '\n', '\x7f', '😀']);
});

test('unsupportedWarning names the characters, control ones by name', () => {
  assert.equal(sendText.unsupportedWarning('plain text'), '');
  assert.equal(sendText.unsupportedWarning('café'), "⚠ Can't type é: only plain ASCII text is supported.");
  assert.equal(sendText.unsupportedWarning('a\r\nb\tc\x01'), "⚠ Can't type line break tab U+0001: only plain ASCII text is supported.");
});

test('pickTextTarget prefers the last ready target, then the first ready device', () => {
  assert.equal(sendText.pickTextTarget(devices, 'B'), 'B');
  assert.equal(sendText.pickTextTarget(devices, 'OFF'), 'A');
  assert.equal(sendText.pickTextTarget(devices, ''), 'A');
  assert.equal(sendText.pickTextTarget([{ serial: 'OFF', status: 'offline' }], 'OFF'), '');
  assert.equal(sendText.pickTextTarget([], 'A'), '');
});

test('cycleTextTarget steps through ready devices and wraps', () => {
  assert.equal(sendText.cycleTextTarget(devices, 'A', 1), 'B');
  assert.equal(sendText.cycleTextTarget(devices, 'C', 1), 'A');
  assert.equal(sendText.cycleTextTarget(devices, 'A', -1), 'C');
  assert.equal(sendText.cycleTextTarget(devices, 'gone', 1), 'A');
  assert.equal(sendText.cycleTextTarget([], 'A', 1), '');
});

const Qt = { A: 0x41, Five: 0x35, Space: 0x20, Tab: 0x01000001, Backtab: 0x01000002, Backspace: 0x01000003, Return: 0x01000004, Escape: 0x01000000, Delete: 0x01000007, Left: 0x01000012, F5: 0x01000034, Ctrl: 0x04000000, Shift: 0x02000000, Alt: 0x08000000 };

test('recordedKey records commands and leaves typing to text', () => {
  assert.equal(sendText.recordedKey(Qt.A, Qt.Ctrl, false), 'ctrl+a');
  assert.equal(sendText.recordedKey(Qt.A, Qt.Ctrl | Qt.Shift, false), 'ctrl+shift+a');
  assert.equal(sendText.recordedKey(Qt.Five, Qt.Alt, false), 'alt+5');
  assert.equal(sendText.recordedKey(Qt.Tab, 0, false), 'tab');
  assert.equal(sendText.recordedKey(Qt.Backtab, Qt.Shift, false), 'shift+tab');
  assert.equal(sendText.recordedKey(Qt.Delete, 0, false), 'del');
  assert.equal(sendText.recordedKey(Qt.Left, 0, false), 'left');
  assert.equal(sendText.recordedKey(Qt.F5, 0, false), 'f5');
  assert.equal(sendText.recordedKey(Qt.Space, Qt.Shift, false), 'shift+space');
  assert.equal(sendText.recordedKey(Qt.Backspace, Qt.Ctrl, false), 'ctrl+backspace');
  for (const [key, mods] of [[Qt.A, 0], [Qt.A, Qt.Shift], [Qt.Space, 0], [Qt.Backspace, 0], [Qt.Return, 0], [Qt.Escape, 0], [0x01000020, Qt.Ctrl]])
    assert.equal(sendText.recordedKey(key, mods, false), '', `${key} ${mods}`);
});

test('recordedKey after Ctrl+K records the prompt keys too', () => {
  assert.equal(sendText.recordedKey(Qt.Backspace, 0, true), 'backspace');
  assert.equal(sendText.recordedKey(Qt.Return, 0, true), 'enter');
  assert.equal(sendText.recordedKey(Qt.Escape, 0, true), 'esc');
  assert.equal(sendText.recordedKey(Qt.A, 0, true), 'a');
});

test('appendText, appendKey and dropLast edit the step list', () => {
  let steps = sendText.appendText([], 'hi');
  steps = sendText.appendKey(steps, 'ctrl+a');
  steps = sendText.appendText(steps, '{x');
  steps = sendText.appendText(steps, '😀');
  assert.deepEqual(plain(steps), [{ text: 'hi' }, { key: 'ctrl+a' }, { text: '{x😀' }]);
  steps = sendText.dropLast(sendText.dropLast(sendText.dropLast(steps)));
  assert.deepEqual(plain(steps), [{ text: 'hi' }, { key: 'ctrl+a' }]);
  assert.deepEqual(plain(sendText.dropLast(steps)), [{ text: 'hi' }]);
  assert.deepEqual(plain(sendText.dropLast([])), []);
  assert.equal(sendText.stepsText([{ text: 'a' }, { key: 'tab' }, { text: 'b' }]), 'ab');
});

test('keyLabel names chips', () => {
  assert.equal(sendText.keyLabel('ctrl+a'), 'Ctrl+A');
  assert.equal(sendText.keyLabel('shift+pageup'), 'Shift+PgUp');
  assert.equal(sendText.keyLabel('f5'), 'F5');
  assert.equal(sendText.keyLabel('backspace'), '⌫ Backspace');
});

test('sendTextCommand keeps the steps out of the arguments; sendTextInput puts them on stdin', () => {
  assert.deepEqual(plain(sendText.sendTextCommand('/p/send-text.sh', 'A')), ['bash', '/p/send-text.sh', 'A']);
  assert.equal(sendText.sendTextInput([{ text: 'hi' }], {}), 'text:hi\n');
  assert.equal(sendText.sendTextInput([{ text: 'hi' }, { key: 'tab' }, { text: '{x}' }], { enter: true }), 'text:hi\nkey:tab\ntext:{x}\nkey:enter\n');
  assert.equal(sendText.sendTextInput([], { clear: true }), 'key:end\nkey:shift+home\nkey:backspace\n');
});
