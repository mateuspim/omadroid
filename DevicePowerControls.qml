import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DevicePower.js" as DevicePower

// Keep awake, wake/unlock, lock and the unlock secret for one ready device, as
// a button row for the device card. The commands live in DevicePowerState,
// which the device page shares; this is only their card-sized view.
ColumnLayout {
  id: root
  required property string serial
  property bool ready: false
  property bool panelOpen: true
  property alias editingSecret: unlockPin.editing
  // Read-through to the shared state, kept so callers and tests/Smoke.qml see
  // the same API as before the state moved out.
  readonly property alias powerState: devicePower
  readonly property var power: devicePower.power
  readonly property string message: devicePower.message
  readonly property bool failed: devicePower.failed
  readonly property bool busy: devicePower.busy
  readonly property bool canUnlock: devicePower.canUnlock
  spacing: Style.space(5)

  function refresh() {
    devicePower.refresh();
  }
  function run(args, stdinText) {
    return devicePower.run(args, stdinText);
  }

  DevicePowerState {
    id: devicePower
    serial: root.serial
    ready: root.ready
    panelOpen: root.panelOpen
  }

  RowLayout {
    objectName: "powerButtons"
    Layout.fillWidth: true
    ActionButton {
      readonly property bool keepAwake: devicePower.keepAwake
      text: (keepAwake ? "✓ " : "○ ") + "Keep awake"
      selected: keepAwake
      enabled: root.power !== null && !root.busy
      tooltipText: keepAwake && !root.power.running ? "On, but not running; it restarts when the device reconnects" : "Keep the screen on, even without mirroring. Android's own timeout returns when turned off"
      Accessible.role: Accessible.CheckBox
      Accessible.checkable: true
      Accessible.checked: keepAwake
      onClicked: devicePower.toggleKeepAwake()
    }
    ActionButton {
      text: root.canUnlock ? "Wake & unlock" : "Wake"
      enabled: !root.busy
      tooltipText: root.canUnlock ? "Turn the screen on and enter the saved PIN once" : "Turn the screen on"
      onClicked: devicePower.wake()
    }
    ActionButton {
      objectName: "powerLock"
      text: "Lock"
      enabled: !root.busy
      tooltipText: "Turn the screen off and lock the device, like its power button"
      onClicked: devicePower.lock()
    }
    ActionButton {
      text: "Unlock PIN…"
      selected: root.editingSecret
      tooltipText: DevicePower.secretLabel(root.power ? root.power.secret : "")
      onClicked: root.editingSecret = !root.editingSecret
    }
  }
  DeviceUnlockPin {
    id: unlockPin
    Layout.fillWidth: true
    powerState: root.powerState
  }
  Label {
    Layout.fillWidth: true
    visible: root.message !== ""
    text: (root.failed ? "⚠ " : "") + root.message
    wrapMode: Text.WordWrap
    color: root.failed ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.7)
  }
}
