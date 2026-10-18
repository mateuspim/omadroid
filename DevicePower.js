/** Parse `device-power.sh status`. Example:
 * parsePowerStatus("keep=on running=1 secret=saved\n") → { keepAwake: true, running: true, secret: "saved" }
 * @param {string} output
 * @returns {{keepAwake: boolean, running: boolean, secret: string}|null} null for anything else
 */
function parsePowerStatus(output) {
  var match = /^keep=(on|off) running=([01]) secret=(none|saved|blocked)$/.exec(String(output).trim());
  if (!match) return null;
  return { keepAwake: match[1] === "on", running: match[2] === "1", secret: match[3] };
}

/** Serials that are ready now but weren't before. Example: newlyReady(["A"], ["A", "B"]) → ["B"].
 * @param {Array<string>} previous @param {Array<string>} current
 * @returns {Array<string>}
 */
function newlyReady(previous, current) {
  return current.filter(function(serial) { return previous.indexOf(serial) < 0; });
}

/** The `device-power.sh connected` command for devices that just became ready.
 * Devices already present when OmaDroid starts only get their keepers back:
 * a shell reload shouldn't wake or unlock anything.
 * Example: connectedCommand("/p/device-power.sh", ["B"], true, false, false) → ["bash", "/p/device-power.sh", "connected", "1", "0", "B"]
 * @returns {Array<string>} empty when there is nothing to do
 */
function connectedCommand(script, serials, wake, unlock, atStartup) {
  if (!serials.length) return [];
  var act = function(flag) { return flag && !atStartup ? "1" : "0"; };
  return ["bash", script, "connected", act(wake), act(unlock)].concat(serials);
}

/** One-line state for the card's Unlock PIN button tooltip. */
function secretLabel(secret) {
  return ({
    none: "No unlock PIN saved",
    saved: "Unlock PIN saved in the keyring; entered once per unlock",
    blocked: "Unlock paused after a failed try; save the PIN again"
  })[secret] || "Unlock PIN state unknown";
}
