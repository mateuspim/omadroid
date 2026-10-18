/** Build the session-helper command which locks the active device's rotation.
 * Rotation values match Android Surface rotation constants:
 * 0 portrait, 1 landscape, 2 inverted portrait and 3 inverted landscape.
 * session.sh resolves the serial from the active session and records that
 * OmaDroid owns the lock, so it can release it when the session ends.
 * Example: orientationCommand("/path/session.sh", 1)
 * @param {string} sessionScript
 * @param {number} rotation
 * @returns {string[]}
 */
function orientationCommand(sessionScript, rotation) {
  validateScript(sessionScript);
  if (!Number.isInteger(rotation) || rotation < 0 || rotation > 3)
    throw new Error("Invalid device rotation " + rotation + "; expected a value from 0 to 3.");
  return ["bash", sessionScript, "rotate", "lock", String(rotation)];
}

/** Build the command which releases Android's rotation lock. Example: autoRotateCommand("/path/session.sh")
 * @param {string} sessionScript @returns {string[]} */
function autoRotateCommand(sessionScript) {
  validateScript(sessionScript);
  return ["bash", sessionScript, "rotate", "free"];
}

/** Build the command which reads the device's current rotation, so the controls
 * reflect the phone after a shell reload. Example: rotationQueryCommand("/path/session.sh")
 * @param {string} sessionScript @returns {string[]} */
function rotationQueryCommand(sessionScript) {
  validateScript(sessionScript);
  return ["bash", sessionScript, "rotate", "query"];
}

function validateScript(sessionScript) {
  if (!sessionScript || /[\x00-\x1f\x7f]/.test(String(sessionScript)))
    throw new Error("Invalid session helper path " + JSON.stringify(sessionScript) + "; expected a file path.");
}

/** Parse `session.sh rotate query` output ("free", or "lock N" optionally followed by "owned").
 * Example: parseRotationState("lock 1\nowned") → { rotation: 1, owned: true }
 * @param {string} text @returns {{rotation: number, owned: boolean}} rotation -1 means auto-rotate */
function parseRotationState(text) {
  var lines = String(text || "").trim().split("\n").map(line => line.trim());
  if (lines[0] === "free")
    return { rotation: -1, owned: false };
  var match = /^lock ([0-3])$/.exec(lines[0]);
  if (!match)
    throw new Error("Unexpected rotation state " + JSON.stringify(text) + "; expected \"free\" or \"lock 0-3\".");
  return { rotation: Number(match[1]), owned: lines[1] === "owned" };
}

function orientationLabel(rotation) {
  return ({
    0: "Portrait",
    1: "Landscape (right)",
    2: "Portrait inverted",
    3: "Landscape (left)"
  })[rotation] || "Unknown orientation";
}

/** Describe the device's rotation state for the status line. Example: rotationStateMessage(1, true)
 * @param {number} rotation @param {boolean} owned @returns {string} */
function rotationStateMessage(rotation, owned) {
  if (rotation < 0)
    return "Auto-rotate enabled.";
  if (owned)
    return orientationLabel(rotation) + " locked. Released when the session stops.";
  return orientationLabel(rotation) + " locked on the phone. Kept after the session stops.";
}

/** session.sh already inspects adb output, so a non-zero exit is the only failure signal. */
function orientationFailure(exitCode, stdoutText, stderrText, action) {
  if (exitCode === 0) return "";
  return "Could not " + action + " (exit " + exitCode + "): " +
    (String(stderrText || "") || String(stdoutText || "") || "adb returned no diagnostic").trim().slice(-1000);
}
