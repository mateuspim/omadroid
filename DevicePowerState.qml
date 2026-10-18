import QtQuick
import "Model.js" as Model
import "DevicePower.js" as DevicePower

// Non-visual power state of one ready device: keep awake, wake/unlock, lock
// and the unlock secret, through device-power.sh. Shared by the card's
// DevicePowerControls and the device page's quick actions and Info section,
// so both run the same commands. The secret only passes through here on its
// way to the keyring, on stdin.
Item {
  id: root
  // Never drawn; hidden so a parent layout leaves no gap for it.
  visible: false
  property string serial: ""
  property bool ready: false
  property bool panelOpen: true
  // Parsed `device-power.sh status`; null until read or when unreadable.
  property var power: null
  property string message: ""
  property bool failed: false
  readonly property bool busy: action.busy
  readonly property bool canUnlock: power !== null && power.secret === "saved"
  readonly property bool keepAwake: power !== null && power.keepAwake
  readonly property string powerScript: decodeURIComponent(Qt.resolvedUrl("device-power.sh").toString().replace(/^file:\/\//, ""))

  Component.onCompleted: refresh()
  // Bindings may set `ready` before `serial` while the card is created.
  onReadyChanged: refresh()
  onSerialChanged: {
    power = null;
    message = "";
    failed = false;
    refresh();
  }
  onPanelOpenChanged: refresh()

  /** Re-read `device-power.sh status` when the device can answer. */
  function refresh() {
    if (serial && ready && panelOpen && !status.busy)
      status.start(["bash", powerScript, "status", serial], 6);
  }
  /** args: device-power.sh arguments, e.g. ["lock", "USB123"]. */
  function run(args, stdinText) {
    failed = false;
    message = "";
    // Unlock: up to 8 s for the bouncer, 10 s typing, 4 s checking.
    return action.start(["bash", powerScript].concat(args), 30, stdinText || "");
  }
  /** Wake the screen, entering the saved PIN once when there is one. */
  function wake() {
    return run([canUnlock ? "unlock" : "wake", serial]);
  }
  function lock() {
    return run(["lock", serial]);
  }
  function toggleKeepAwake() {
    return run(["keep-awake", keepAwake ? "off" : "on", serial]);
  }
  /** Store `secret` in the keyring; shorter than 4 characters is refused. */
  function saveSecret(secret) {
    if (String(secret).length < 4 || busy)
      return false;
    return run(["secret-set", serial], secret + "\n");
  }
  function forgetSecret() {
    return run(["secret-clear", serial]);
  }

  Command {
    id: status
    onFinished: (code, output, error) => root.power = code === 0 ? DevicePower.parsePowerStatus(output) : null
  }
  Command {
    id: action
    onFinished: (code, output, error) => {
      root.failed = code !== 0;
      root.message = root.failed ? Model.commandError(code, output, error, "Device power") : output.trim().split("\n").pop();
      root.refresh();
    }
  }
}
