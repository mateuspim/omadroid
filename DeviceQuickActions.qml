import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The device page's quick actions: a grid of icon-over-label tiles, one per
// DeviceActions.deviceActions() entry. The grid only draws; DevicePage runs
// the action named by `triggered(key)`.
GridLayout {
  id: root
  // [{key, icon, label, tooltip, enabled, selected}]
  property var entries: []
  signal triggered(string key)
  columns: 4
  columnSpacing: Style.space(6)
  rowSpacing: Style.space(6)

  Repeater {
    model: root.entries
    delegate: Button {
      id: tile
      required property var modelData
      objectName: "quickAction:" + modelData.key
      // Equal columns whatever the labels: the tiles share the width instead
      // of each asking for its label's.
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.minimumWidth: 0
      implicitHeight: tileContent.implicitHeight + Style.space(16)
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

      readonly property color tint: selected ? Style.selectedStateColor(Color.foreground, Color.accent) : Color.foreground
      Column {
        id: tileContent
        anchors.centerIn: parent
        width: parent.width - Style.space(8)
        spacing: Style.space(2)
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: tile.modelData.icon
          color: tile.tint
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: tile.modelData.label
          color: tile.tint
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: tile.selected
        }
      }
    }
  }
}
