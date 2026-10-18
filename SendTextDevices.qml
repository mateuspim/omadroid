import QtQuick
import qs.Commons
import qs.Commons as Commons

// The Send text overlay's device row: every ready device, the target
// highlighted. Alt+←/→ in the overlay moves the highlight when there are several.
Flow {
  id: root

  property var devices: []
  property string target: ""
  property color foreground: Commons.Color.menu.text
  property string fontFamily: Style.font.menuFamily

  spacing: Style.spacing.controlPaddingX

  Text {
    visible: root.devices.length === 0
    textFormat: Text.PlainText
    text: "⚠ No device ready. Connect one with OmaDroid first."
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.devices

    Rectangle {
      id: chip
      required property var modelData
      readonly property bool selected: modelData.serial === root.target
      objectName: "sendTextDevice:" + modelData.serial
      width: label.implicitWidth + Style.spacing.controlPaddingX * 2
      height: label.implicitHeight + Style.spacing.controlPaddingY * 2
      radius: Style.cornerRadius
      color: selected ? Commons.Color.menu.selectedBackground : "transparent"
      border.width: selected ? 0 : 1
      border.color: Qt.alpha(root.foreground, 0.2)

      Text {
        id: label
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: (chip.modelData.name || chip.modelData.serial) + (root.devices.length > 1 ? " · " + chip.modelData.transport : "")
        color: chip.selected ? Commons.Color.menu.selectedText : root.foreground
        opacity: chip.selected ? 1 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  Text {
    visible: root.devices.length > 1
    textFormat: Text.PlainText
    text: "Alt+←/→ to switch"
    color: root.foreground
    opacity: 0.58
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
