/** Build an Android rotation-lock command for the selected device.
 * Rotation values match Android Surface rotation constants:
 * 0 portrait, 1 landscape, 2 inverted portrait and 3 inverted landscape.
 * @param {string} serial
 * @param {number} rotation
 * @returns {string[]}
 */
function orientationCommand(serial, rotation) {
  validateSerial(serial);
  if (!Number.isInteger(rotation) || rotation < 0 || rotation > 3)
    throw new Error("Invalid device rotation " + rotation + "; expected a value from 0 to 3.");
  return ["adb", "-s", serial, "shell", "wm", "user-rotation", "lock", String(rotation)];
}

/** Build the command which releases Android's rotation lock. @param {string} serial @returns {string[]} */
function autoRotateCommand(serial) {
  validateSerial(serial);
  return ["adb", "-s", serial, "shell", "wm", "user-rotation", "free"];
}

function validateSerial(serial) {
  if (!serial || /[\x00-\x1f\x7f]/.test(String(serial)))
    throw new Error("Select an authorized Android device.");
}

function orientationLabel(rotation) {
  return ({
    0: "Portrait",
    1: "Landscape (right)",
    2: "Portrait inverted",
    3: "Landscape (left)"
  })[rotation] || "Unknown orientation";
}

/** Treat only a clean adb exit without an explicit error as success. */
function orientationFailure(exitCode, stdoutText, stderrText, action) {
  var output = String(stdoutText || "");
  var error = String(stderrText || "");
  if (exitCode === 0 && !/(?:failed|error|unknown command|permission denied)/i.test(output + "\n" + error)) return "";
  return "Could not " + action + " (exit " + exitCode + "): " +
    (error || output || "adb returned no diagnostic").trim().slice(-1000);
}
