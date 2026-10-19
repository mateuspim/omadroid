// The Send text overlay's pure parts: what may be typed and which device gets it.
// `adb shell input text` only types printable ASCII reliably; send-text.sh
// checks the same rule and does the quoting for the device's sh.

/** Characters `input text` can't type, each listed once, in order.
 * Example: unsupportedChars("café ok") → ["é"]
 * @param {string} text @returns {Array<string>}
 */
function unsupportedChars(text) {
  var found = [];
  Array.from(String(text)).forEach(function(ch) {
    var code = ch.codePointAt(0);
    if ((code < 32 || code > 126) && found.indexOf(ch) < 0)
      found.push(ch);
  });
  return found;
}

/** How a character is named in the warning: control characters by name or code.
 * Example: charLabel("\n") → "line break"
 * @param {string} ch @returns {string}
 */
function charLabel(ch) {
  var names = { "\n": "line break", "\r": "line break", "\t": "tab" };
  if (names[ch])
    return names[ch];
  var code = ch.codePointAt(0);
  return code < 32 || code === 127 ? "U+" + ("000" + code.toString(16).toUpperCase()).slice(-4) : ch;
}

/** The warning shown instead of sending, or "" when the text can be typed.
 * Example: unsupportedWarning("café") → "⚠ Can't type é: only plain ASCII text is supported."
 * @param {string} text @returns {string}
 */
function unsupportedWarning(text) {
  var labels = unsupportedChars(text).map(charLabel).filter(function(label, i, all) { return all.indexOf(label) === i; });
  if (!labels.length)
    return "";
  return "⚠ Can't type " + labels.join(" ") + ": only plain ASCII text is supported.";
}

/** Serials of the devices adb lists as ready ("device").
 * @param {Array<{serial: string, status: string}>} devices @returns {Array<string>}
 */
function readySerials(devices) {
  return (devices || []).filter(function(row) { return row.status === "device"; }).map(function(row) { return row.serial; });
}

/** The device text goes to: the last one sent to while it is ready, else the first ready one.
 * Example: pickTextTarget([{serial: "A", status: "device"}], "B") → "A"
 * @param {Array<{serial: string, status: string}>} devices @param {string} lastSerial
 * @returns {string} "" when no device is ready
 */
function pickTextTarget(devices, lastSerial) {
  var ready = readySerials(devices);
  if (ready.indexOf(lastSerial) >= 0)
    return lastSerial;
  return ready.length ? ready[0] : "";
}

/** The ready device `step` places from `serial`, wrapping around (←/→ in the overlay).
 * Example: cycleTextTarget(devices, "A", 1) → "B" when A and B are ready
 * @param {Array<{serial: string, status: string}>} devices @param {string} serial @param {number} step
 * @returns {string} "" when no device is ready
 */
function cycleTextTarget(devices, serial, step) {
  var ready = readySerials(devices);
  if (!ready.length)
    return "";
  var index = ready.indexOf(serial);
  if (index < 0)
    return ready[0];
  return ready[((index + step) % ready.length + ready.length) % ready.length];
}

// Qt key codes (Qt::Key) and modifier bits (Qt::KeyboardModifier), fixed by Qt's ABI.
var qtKeys = {
  0x01000000: "esc", 0x01000001: "tab", 0x01000003: "backspace", 0x01000004: "enter", 0x01000005: "enter",
  0x01000006: "insert", 0x01000007: "del", 0x01000010: "home", 0x01000011: "end", 0x01000012: "left",
  0x01000013: "up", 0x01000014: "right", 0x01000015: "down", 0x01000016: "pageup", 0x01000017: "pagedown",
  0x01000055: "menu", 0x20: "space"
};
var qtModifiers = [[0x04000000, "ctrl"], [0x08000000, "alt"], [0x02000000, "shift"], [0x10000000, "meta"]];
// Keys the prompt keeps for itself when pressed without Ctrl, Alt or Meta:
// they send, close or edit the prompt. Ctrl+K first records them anyway.
var plainOnlyAfterLiteral = ["esc", "backspace", "enter"];

/** The send-text.sh name of a Qt key: letters, digits, F1–F12 and qtKeys.
 * Example: qtKeyName(0x41) → "a" @param {number} key @returns {string} "" when unknown */
function qtKeyName(key) {
  if ((key >= 0x41 && key <= 0x5a) || (key >= 0x30 && key <= 0x39))
    return String.fromCharCode(key).toLowerCase();
  if (key >= 0x01000030 && key <= 0x0100003b)
    return "f" + (key - 0x01000030 + 1);
  if (key === 0x01000002) // Backtab: what Shift+Tab arrives as.
    return "tab";
  return qtKeys[key] || "";
}

/** The key a press records as a chip, or "" when it types text or belongs to
 * the prompt. Plain letters and digits type; with Ctrl, Alt or Meta they record.
 * `literal` (after Ctrl+K) records any key, Enter and Backspace included.
 * Example: recordedKey(0x41, 0x04000000, false) → "ctrl+a"
 * @param {number} key @param {number} modifiers @param {boolean} literal @returns {string}
 */
function recordedKey(key, modifiers, literal) {
  var name = qtKeyName(key);
  var mods = qtModifiers.filter(function(pair) { return (modifiers & pair[0]) !== 0; }).map(function(pair) { return pair[1]; });
  if (key === 0x01000002 && mods.indexOf("shift") < 0)
    mods.push("shift");
  if (!name)
    return "";
  var typesText = /^[a-z0-9]$/.test(name) || name === "space";
  var commanding = mods.some(function(mod) { return mod !== "shift"; });
  if (literal || commanding)
    return mods.concat([name]).join("+");
  if (plainOnlyAfterLiteral.indexOf(name) >= 0 || (typesText && !(name === "space" && mods.length)))
    return "";
  return mods.concat([name]).join("+");
}

/** Steps with `text` typed at the end, joined to a text step already there.
 * Example: appendText([{text: "a"}], "b") → [{text: "ab"}]
 * @param {Array<{text: string}|{key: string}>} steps @param {string} text @returns {Array} */
function appendText(steps, text) {
  var last = steps[steps.length - 1];
  if (!text)
    return steps;
  if (last && "text" in last)
    return steps.slice(0, -1).concat([{ text: last.text + text }]);
  return steps.concat([{ text: text }]);
}

/** Steps with one more key. Example: appendKey([], "ctrl+a") → [{key: "ctrl+a"}] */
function appendKey(steps, name) {
  return steps.concat([{ key: name }]);
}

/** Backspace in the prompt: the last character, or the last key chip.
 * Example: dropLast([{key: "tab"}, {text: "hi"}]) → [{key: "tab"}, {text: "h"}] */
function dropLast(steps) {
  var last = steps[steps.length - 1];
  if (!last || "key" in last)
    return steps.slice(0, -1);
  var chars = Array.from(last.text).slice(0, -1).join("");
  return steps.slice(0, -1).concat(chars ? [{ text: chars }] : []);
}

/** All typed text, for the ASCII check. Example: stepsText([{text: "a"}, {key: "tab"}, {text: "b"}]) → "ab" */
function stepsText(steps) {
  return steps.map(function(step) { return step.text || ""; }).join("");
}

/** A chip's label. Example: keyLabel("ctrl+shift+pageup") → "Ctrl+Shift+PgUp" */
function keyLabel(name) {
  var labels = { ctrl: "Ctrl", alt: "Alt", shift: "Shift", meta: "Super", del: "Delete", esc: "Esc", pageup: "PgUp", pagedown: "PgDn", backspace: "⌫ Backspace", enter: "↵ Enter", tab: "⇥ Tab", left: "←", right: "→", up: "↑", down: "↓" };
  return name.split("+").map(function(part) { return labels[part] || part.charAt(0).toUpperCase() + part.slice(1); }).join("+");
}

// Clearing the focused field selects it with End, Shift+Home and deletes. Not
// Ctrl+A: some apps react to Ctrl alone (YouTube opens its shortcut list on any
// Ctrl press, which then swallows the keys after it). Only the last line of a
// multi-line field is selected this way.
var clearFieldKeys = ["key:end", "key:shift+home", "key:backspace"];

/** The send-text.sh command. The steps go on its stdin (sendTextInput), so
 * typed text never shows in a process listing.
 * Example: sendTextCommand("/p/send-text.sh", "A") → ["bash", "/p/send-text.sh", "A"]
 * @param {string} script @param {string} serial @returns {Array<string>}
 */
function sendTextCommand(script, serial) {
  return ["bash", script, serial];
}

/** send-text.sh's stdin: optionally clear the focused field first, then the
 * steps, then optionally Enter, one per line. Text steps can't hold a line
 * break: unsupportedChars refuses it before anything is sent.
 * Example: sendTextInput([{text: "hi"}], { clear: true }) → "key:end\nkey:shift+home\nkey:backspace\ntext:hi\n"
 * @param {Array<{text: string}|{key: string}>} steps @param {{clear: boolean, enter: boolean}} options
 * @returns {string}
 */
function sendTextInput(steps, options) {
  var lines = steps.map(function(step) { return "text" in step ? "text:" + step.text : "key:" + step.key; });
  var before = options && options.clear ? clearFieldKeys : [];
  var after = options && options.enter ? ["key:enter"] : [];
  return before.concat(lines, after).map(function(line) { return line + "\n"; }).join("");
}
