import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The device page's controls: one compact row of icon + short label buttons,
// one per DeviceActions.deviceControls() entry, below the session cards so
// they weigh less than starting a session. The row only draws; DevicePage
// runs the control named by `triggered(key)`.
//
// Usage: DeviceControls { entries: DeviceActions.deviceControls(row, state); onTriggered: key => run(key) }
RowLayout {
  id: root
  // [{key, icon, label, tooltip, enabled, selected}]
  property var entries: []
  signal triggered(string key)
  spacing: Style.space(4)

  Repeater {
    model: root.entries
    delegate: Button {
      id: control
      required property var modelData
      objectName: "deviceControl:" + modelData.key
      // Each asks for its own label's width and the row shares what is left,
      // so short labels never squeeze a long one ("Disconnect").
      Layout.fillWidth: true
      Layout.preferredWidth: implicitWidth
      Layout.minimumWidth: 0
      iconText: modelData.icon
      text: modelData.label
      fontSize: Style.font.bodySmall
      iconSize: Style.font.body
      horizontalPadding: Style.space(6)
      bordered: true
      focusable: true
      enabled: modelData.enabled
      opacity: enabled ? 1 : 0.4
      selected: modelData.selected
      tooltipText: modelData.tooltip
      Accessible.role: modelData.key === "keepAwake" ? Accessible.CheckBox : Accessible.Button
      Accessible.name: modelData.label
      Accessible.checkable: modelData.key === "keepAwake"
      Accessible.checked: modelData.selected
      onClicked: root.triggered(modelData.key)
    }
  }
}
