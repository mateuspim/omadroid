import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DeviceInfo.js" as DeviceInfo
import "Model.js" as Model
import "DevicePage.js" as DevicePage
import "DevicePower.js" as DevicePower

// The device page's Info section: what device-info.sh read, the serial and
// address with copy buttons, and the unlock PIN kept in the keyring.
ColumnLayout {
  id: root
  required property var device
  // The page's DevicePowerState, shared with the quick actions.
  required property var powerState
  readonly property var details: DeviceInfo.deviceDetails(device.info)
  property string copied: ""
  property string copyError: ""
  spacing: Style.space(8)

  /** Put `value` on the Wayland clipboard; `label` names it in the feedback. */
  function copy(label, value) {
    copyError = "";
    copied = clipboard.start(["wl-copy", "--type", "text/plain"], 4, value) ? label : "";
  }

  PanelSectionHeader {
    Layout.fillWidth: true
    text: "DETAILS"
  }
  Label {
    Layout.fillWidth: true
    visible: root.details.length === 0
    text: root.device.status === "device" ? "Reading battery, storage and memory…" : "Details appear once the device is ready."
    color: Util.alpha(Commons.Color.foreground, 0.7)
  }
  GridLayout {
    Layout.fillWidth: true
    visible: root.details.length > 0
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(4)
    Repeater {
      model: root.details.reduce((cells, row) => cells.concat([row.label, row.value]), [])
      delegate: Label {
        required property var modelData
        required property int index
        readonly property bool isValue: index % 2 === 1
        Layout.fillWidth: isValue
        Layout.preferredWidth: isValue ? 1 : -1
        Layout.alignment: Qt.AlignTop
        text: modelData
        wrapMode: isValue ? Text.WordWrap : Text.NoWrap
        color: isValue ? Commons.Color.foreground : Util.alpha(Commons.Color.foreground, 0.7)
      }
    }
  }

  PanelSeparator {
    Layout.fillWidth: true
  }
  PanelSectionHeader {
    Layout.fillWidth: true
    text: "CONNECTION"
  }
  Repeater {
    model: DevicePage.identityRows(root.device)
    delegate: RowLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(12)
      Label {
        text: modelData.label
        wrapMode: Text.NoWrap
        color: Util.alpha(Commons.Color.foreground, 0.7)
      }
      Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        text: modelData.value
        wrapMode: Text.NoWrap
        elide: Text.ElideMiddle
      }
      PanelActionButton {
        objectName: "copy:" + modelData.label
        iconText: "󰆏"
        tooltipText: "Copy " + modelData.label.toLowerCase()
        Accessible.role: Accessible.Button
        Accessible.name: "Copy " + modelData.label.toLowerCase()
        onClicked: root.copy(modelData.label, modelData.value)
      }
    }
  }
  Label {
    Layout.fillWidth: true
    visible: root.copied !== "" || root.copyError !== ""
    text: root.copyError ? "⚠ " + root.copyError : root.copied + " copied."
    color: root.copyError ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.7)
    font.pixelSize: Style.font.bodySmall
  }

  PanelSeparator {
    Layout.fillWidth: true
    visible: root.device.status === "device"
  }
  PanelSectionHeader {
    Layout.fillWidth: true
    visible: root.device.status === "device"
    text: "UNLOCK PIN"
  }
  RowLayout {
    Layout.fillWidth: true
    visible: root.device.status === "device"
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: DevicePower.secretLabel(root.powerState.power ? root.powerState.power.secret : "")
      wrapMode: Text.WordWrap
      color: root.powerState.power && root.powerState.power.secret === "blocked" ? Commons.Color.urgent : Commons.Color.foreground
    }
    ActionButton {
      objectName: "unlockPinEdit"
      text: unlockPin.editing ? "Cancel" : root.powerState.power && root.powerState.power.secret !== "none" ? "Change…" : "Set…"
      enabled: root.powerState.power !== null
      onClicked: unlockPin.editing = !unlockPin.editing
    }
  }
  DeviceUnlockPin {
    id: unlockPin
    Layout.fillWidth: true
    powerState: root.powerState
  }

  Command {
    id: clipboard
    onFinished: (code, output, error) => {
      if (code === 0)
        return;
      root.copied = "";
      root.copyError = Model.commandError(code, output, error, "Copy");
    }
  }
  // The feedback is for the click just made, not for a later visit.
  Timer {
    running: root.copied !== ""
    interval: 3000
    onTriggered: root.copied = ""
  }
}
