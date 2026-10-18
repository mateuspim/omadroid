import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DeviceListModel.js" as DeviceList

// One compact home-list row, after Omarchy's Bluetooth panel: glyph, name,
// one dim line, and either a chevron (ready: the whole row opens the device)
// or a single inline action. Serial and address live in the tooltip.
CursorSurface {
  id: root
  required property var row
  // Gates the inline action while Actions runs a command.
  property bool actionsBusy: false
  readonly property var action: DeviceList.deviceRowAction(row)
  readonly property bool opens: action.kind === "open"
  readonly property bool attention: DeviceList.deviceGroupKey(row) === "attention"
  // Emitted for ready rows (click, Enter or Space).
  signal activated
  // Emitted with deviceRowAction(row).kind for the inline button.
  signal actionRequested(string kind)

  implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX
  hasCursor: opens && (rowMouse.containsMouse || activeFocus)
  activeFocusOnTab: true
  Accessible.role: opens ? Accessible.Button : Accessible.ListItem
  Accessible.name: row.name + ", " + DeviceList.deviceSubtitle(row)
  Accessible.description: DeviceList.deviceRowTooltip(row)
  Accessible.onPressAction: trigger()
  Keys.onReturnPressed: trigger()
  Keys.onEnterPressed: trigger()
  Keys.onSpacePressed: trigger()

  // Keyboard users reach the inline action through the row itself, so a
  // non-ready row needs no second tab stop.
  function trigger() {
    if (opens)
      activated();
    else if (action.kind !== "" && !actionsBusy)
      actionRequested(action.kind);
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.opens ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.opens) root.activated()
  }

  PanelToolTip {
    visible: rowMouse.containsMouse
    text: DeviceList.deviceRowTooltip(root.row)
  }

  RowLayout {
    id: content
    anchors {
      left: parent.left
      right: parent.right
      verticalCenter: parent.verticalCenter
      leftMargin: Style.space(10)
      rightMargin: Style.space(6)
    }
    spacing: Style.space(10)

    Text {
      Layout.preferredWidth: Style.space(20)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: DeviceList.transportGlyph(root.row)
      color: root.opens ? Commons.Color.accent : root.attention ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
    }
    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      spacing: Style.space(1)
      Label {
        Layout.fillWidth: true
        text: root.row.name
        font.bold: true
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      Label {
        Layout.fillWidth: true
        text: DeviceList.deviceSubtitle(root.row)
        color: root.attention ? Util.alpha(Commons.Color.urgent, 0.85) : Util.alpha(Commons.Color.foreground, 0.6)
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
    }
    Text {
      visible: root.opens
      textFormat: Text.PlainText
      text: "›"
      color: Util.alpha(Commons.Color.foreground, root.hasCursor ? 0.9 : 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      Layout.rightMargin: Style.space(4)
    }
    Button {
      visible: !root.opens && root.action.kind !== ""
      text: root.action.label
      tooltipText: root.action.tooltip
      bordered: true
      fontSize: Style.font.bodySmall
      horizontalPadding: Style.space(8)
      verticalPadding: Style.space(3)
      enabled: !root.actionsBusy
      opacity: enabled ? 1 : 0.45
      Accessible.name: root.action.label + " " + root.row.name
      onClicked: root.actionRequested(root.action.kind)
    }
  }
}
