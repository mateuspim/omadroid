import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One big session card on the device page (Mirror, Audio or Webcam): icon,
// name, and a two-line subtitle that says what a click would start, or the
// state ("● Running", "Switching…", "Switch · stops …"). The ⚙ in its corner
// toggles the card's options below the cards. It only draws; DeviceSessions
// decides what a click does.
//
// Public API
//   entry        one DeviceActions.sessionCards() card
//                {key, icon, label, subtitle, tooltip, enabled, running, urgent, action}
//   optionsOpen  this card's options are shown (the ⚙ lights up)
//   signal clicked()          (Button's) the card was clicked
//   signal optionsToggled()   the ⚙ was clicked
//
// Usage:
//   SessionTile { entry: cards[0]; onClicked: sessions.activate(entry.key) }
Button {
  id: root
  required property var entry
  property bool optionsOpen: false
  signal optionsToggled

  objectName: "sessionCard:" + entry.key
  // Three cards share the row whatever their text: none asks for its label's width.
  Layout.fillWidth: true
  Layout.preferredWidth: 1
  Layout.minimumWidth: 0
  implicitHeight: tileContent.implicitHeight + Style.space(20)
  bordered: true
  focusable: true
  enabled: entry.enabled
  opacity: enabled ? 1 : 0.45
  // The theme's selected fill is grey; a running or confirming card is
  // tinted instead, with the accent (or urgent) outline drawn below.
  background: Util.alpha(highlight, entry.running || entry.urgent ? 0.1 : 0)
  tooltipText: entry.tooltip
  Accessible.role: Accessible.Button
  Accessible.name: entry.label + ", " + entry.subtitle

  readonly property color highlight: entry.urgent ? Color.urgent : Color.accent
  readonly property color tint: entry.urgent || entry.running ? highlight : Color.foreground

  Rectangle {
    anchors.fill: parent
    visible: root.entry.running || root.entry.urgent
    radius: root.radius
    color: "transparent"
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Util.alpha(root.highlight, 0.7)
  }

  ColumnLayout {
    id: tileContent
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: Style.space(10)
    }
    spacing: Style.space(4)
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Text {
        textFormat: Text.PlainText
        text: root.entry.icon
        color: root.tint
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
      }
      Text {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        textFormat: Text.PlainText
        text: root.entry.label
        color: root.tint
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      // Above the card's own click area, so it opens the options instead of starting.
      PanelActionButton {
        objectName: "sessionOptions:" + root.entry.key
        iconText: "󰒓"
        fontSize: Style.font.bodySmall
        size: Style.space(20)
        foreground: root.optionsOpen ? Color.accent : Util.alpha(Color.foreground, 0.6)
        hoverColor: Color.accent
        tooltipText: (root.optionsOpen ? "Hide " : "Show ") + root.entry.label.toLowerCase() + " options"
        Accessible.role: Accessible.Button
        Accessible.name: root.entry.label + " options"
        Accessible.checkable: true
        Accessible.checked: root.optionsOpen
        onClicked: root.optionsToggled()
      }
    }
    // Always two lines tall, so the cards keep one height whatever they say.
    Text {
      objectName: "sessionSubtitle:" + root.entry.key
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.minimumHeight: Math.ceil(subtitleMetrics.lineSpacing * 2)
      textFormat: Text.PlainText
      text: root.entry.subtitle
      color: root.entry.urgent ? Color.urgent : root.entry.running ? Color.accent : Util.alpha(Color.foreground, 0.65)
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      verticalAlignment: Text.AlignTop
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.entry.running || root.entry.urgent
    }
  }
  FontMetrics {
    id: subtitleMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
}
