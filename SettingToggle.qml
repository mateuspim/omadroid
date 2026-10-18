import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A Settings row: Omarchy's labeled Toggle (title, one-line description,
// switch on the right) plus a tooltip for the longer explanation.
// Example: SettingToggle { label: "Wake"; description: "Turn the screen on"; checked: on; onClicked: flip() }
Toggle {
  id: root
  property string detail: ""
  Layout.fillWidth: true
  Layout.preferredWidth: 1
  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.description: description
  Accessible.checkable: true
  Accessible.checked: checked

  HoverHandler {
    id: toggleHover
  }
  PanelToolTip {
    visible: toggleHover.hovered && root.detail !== ""
    text: root.detail
  }
}
