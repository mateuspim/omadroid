import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "DevicePower.js" as DevicePower

// Keep awake, wake/unlock and the unlock secret for one ready device. Device
// and keyring access goes through device-power.sh; the secret only passes
// through here on its way to the keyring, on stdin.
ColumnLayout {
  id: root
  required property string serial
  property bool ready: false
  property bool panelOpen: true
  // Parsed `device-power.sh status`; null until read or when unreadable.
  property var power: null
  property string message: ""
  property bool failed: false
  property bool editingSecret: false
  readonly property bool busy: action.busy
  readonly property bool canUnlock: power !== null && power.secret === "saved"
  readonly property string powerScript: decodeURIComponent(Qt.resolvedUrl("device-power.sh").toString().replace(/^file:\/\//, ""))
  spacing: Style.space(5)

  Component.onCompleted: refresh()
  // Bindings may set `ready` before `serial` while the card is created.
  onReadyChanged: refresh()
  onSerialChanged: refresh()
  onPanelOpenChanged: {
    if (panelOpen)
      return refresh();
    editingSecret = false;
    secretField.text = "";
  }

  function refresh() {
    if (serial && ready && panelOpen && !status.busy)
      status.start(["bash", powerScript, "status", serial], 6);
  }
  function run(args, stdinText) {
    failed = false;
    message = "";
    // Unlock: up to 8 s for the bouncer, 10 s typing, 4 s checking.
    action.start(["bash", powerScript].concat(args), 30, stdinText || "");
  }
  function saveSecret() {
    if (secretField.text.length < 4 || busy)
      return;
    run(["secret-set", serial], secretField.text + "\n");
    secretField.text = "";
    editingSecret = false;
  }

  RowLayout {
    Layout.fillWidth: true
    ActionButton {
      readonly property bool keepAwake: root.power !== null && root.power.keepAwake
      text: (keepAwake ? "✓ " : "○ ") + "Keep awake"
      selected: keepAwake
      enabled: root.power !== null && !root.busy
      tooltipText: keepAwake && !root.power.running ? "On, but not running; it restarts when the device reconnects" : "Keep the screen on, even without mirroring. Android's own timeout returns when turned off"
      Accessible.role: Accessible.CheckBox
      Accessible.checkable: true
      Accessible.checked: keepAwake
      onClicked: root.run(["keep-awake", keepAwake ? "off" : "on", root.serial])
    }
    ActionButton {
      text: root.canUnlock ? "Wake & unlock" : "Wake"
      enabled: !root.busy
      tooltipText: root.canUnlock ? "Turn the screen on and enter the saved PIN once" : "Turn the screen on"
      onClicked: root.run([root.canUnlock ? "unlock" : "wake", root.serial])
    }
    ActionButton {
      text: "Unlock PIN…"
      selected: root.editingSecret
      tooltipText: DevicePower.secretLabel(root.power ? root.power.secret : "")
      onClicked: {
        root.editingSecret = !root.editingSecret;
        if (root.editingSecret)
          Qt.callLater(() => secretField.forceActiveFocus());
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    visible: root.editingSecret
    TextField {
      id: secretField
      Layout.fillWidth: true
      placeholderText: "Device PIN or password"
      password: true
      maximumLength: 64
      inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
      Accessible.name: "Device PIN or password"
      onAccepted: root.saveSecret()
    }
    ActionButton {
      text: "Save"
      enabled: secretField.text.length >= 4 && !root.busy
      onClicked: root.saveSecret()
    }
    ActionButton {
      text: "Forget"
      visible: root.power !== null && root.power.secret !== "none"
      enabled: !root.busy
      onClicked: {
        root.run(["secret-clear", root.serial]);
        root.editingSecret = false;
      }
    }
  }
  Label {
    Layout.fillWidth: true
    visible: root.editingSecret
    text: "Kept in your desktop keyring, never in DroidLink's settings. It is entered once per unlock; a failed try pauses unlocking until you save it again."
    wrapMode: Text.WordWrap
    font.pixelSize: Style.font.bodySmall
    color: Util.alpha(Color.foreground, 0.7)
  }
  Label {
    Layout.fillWidth: true
    visible: root.message !== ""
    text: (root.failed ? "⚠ " : "") + root.message
    wrapMode: Text.WordWrap
    color: root.failed ? Color.urgent : Util.alpha(Color.foreground, 0.7)
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
