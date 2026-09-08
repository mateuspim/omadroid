/** Target scrcpy's own display-power shortcut; never use the focused window.
 * Example: screenPowerKeyCommand(1234, true, false) releases Alt+Shift+O.
 * @param {number} sessionPid
 * @param {boolean} screenOn
 * @param {boolean} pressed
 * @returns {string[]}
 */
function screenPowerKeyCommand(sessionPid, screenOn, pressed) {
  if (!Number.isSafeInteger(sessionPid) || sessionPid <= 0)
    throw new Error("Invalid session PID " + sessionPid + "; expected a positive integer for the running scrcpy child.");
  if (typeof screenOn !== "boolean" || typeof pressed !== "boolean")
    throw new Error("Invalid screen/key state " + screenOn + "/" + pressed + "; expected two booleans.");
  var modifiers = screenOn ? "ALT + SHIFT" : "ALT";
  var keyState = pressed ? "down" : "up";
  return ["hyprctl", "dispatch", "hl.dsp.send_key_state({mods=\"" + modifiers + "\",key=\"O\",state=\"" + keyState + "\",window=\"pid:" + sessionPid + "\"})"];
}

/** Treat only the compositor's explicit acknowledgement as success.
 * Example: screenPowerFailure(0, "ok\n", "") returns an empty string.
 * @param {number} exitCode
 * @param {string} stdoutText
 * @param {string} stderrText
 * @returns {string}
 */
function screenPowerFailure(exitCode, stdoutText, stderrText) {
  if (exitCode === 0 && stdoutText.trim() === "ok" && !stderrText.trim()) return "";
  return "Screen control failed (exit " + exitCode + "): " +
    (stderrText || stdoutText || "expected an 'ok' reply from Hyprland").trim().slice(-1000) +
    ". In the scrcpy window, use Alt+Shift+O for screen on or Alt+O for screen off.";
}
