import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One muted line of help under a control, with the longer explanation in a
// tooltip so pages stay short. Starts with "⚠ " and turns urgent for errors.
// Example: HintLabel { text: "Scan with Android"; detail: "Android 11 or later." }
Label {
  id: root
  property string detail: ""
  property bool urgent: false
  Layout.fillWidth: true
  // A wrapped Label reports its unwrapped width; this keeps it from widening the popup.
  Layout.preferredWidth: 1
  color: urgent ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.65)
  font.pixelSize: Style.font.bodySmall
  wrapMode: Text.WordWrap
  Accessible.description: detail

  HoverHandler {
    id: hintHover
    enabled: root.detail !== ""
  }
  PanelToolTip {
    visible: hintHover.hovered && root.detail !== ""
    text: root.detail
  }
}
