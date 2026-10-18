import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "DeviceListModel.js" as DeviceList

// Home view: Discovery rows grouped into CONNECTED / NEEDS ATTENTION / NEARBY,
// status lines on top, "+ Add device" at the end.
//
// Connect, Reconnect and Disconnect run through `actions` here. A Connect on
// an mDNS row that fails to authenticate means the phone isn't paired yet, so
// the list emits pairDevice(row) once Actions reports the failure — the host
// opens Add device prefilled (connectionForm.beginPair(row, rows, true)) and
// no longer needs its own pendingPairFallback / actions.onChanged handler.
ColumnLayout {
  id: root
  // Discovery.rows.
  property var rows: []
  // The Actions.qml instance shared with the Add device page.
  property var actions: null
  // Discovery is scanning; shown only while there is nothing to list yet.
  property bool busy: false
  property bool initialized: true
  property string devicesError: ""
  property string mdnsError: ""
  property string mdnsLevel: ""
  property string mdnsDetails: ""
  // The mDNS row whose Connect may need to fall back to pairing.
  property var pendingPairFallback: null
  readonly property var groups: DeviceList.deviceGroups(rows)
  readonly property bool actionsBusy: !!actions && actions.busy
  signal openDevice(string serial)
  signal pairDevice(var row)
  signal addDevice

  spacing: Style.space(10)

  /** Run a row's inline action. Example: runRowAction(nearbyRow, "connect") */
  function runRowAction(row, kind) {
    if (kind === "pair")
      return pairDevice(row);
    if (kind === "disconnect")
      return actions.run("disconnect", row.serial, "");
    pendingPairFallback = kind === "connect" ? row : null;
    if (!actions.run("connect", row.endpoint, ""))
      pendingPairFallback = null;
  }

  Connections {
    target: root.actions
    ignoreUnknownSignals: true
    function onChanged() {
      var row = root.pendingPairFallback;
      root.pendingPairFallback = null;
      if (Model.needsPairingFallback(row, root.actions.failed))
        root.pairDevice(row);
    }
  }

  StatusLine {
    visible: root.actions && root.actions.message !== ""
    text: root.actions ? (root.actions.failed ? "⚠ " : "") + root.actions.message : ""
    color: root.actions && root.actions.failed ? Commons.Color.urgent : Commons.Color.accent
  }
  StatusLine {
    visible: root.devicesError !== ""
    text: "⚠ ADB: " + root.devicesError
    color: Commons.Color.urgent
  }
  // A warning (a device didn't answer) is muted; a hard failure is urgent.
  // The raw Avahi output stays in the tooltip.
  StatusLine {
    visible: root.mdnsError !== ""
    text: root.mdnsLevel === "error" ? "⚠ Wireless discovery: " + root.mdnsError : root.mdnsError
    color: root.mdnsLevel === "error" ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.6)
    tooltip: root.mdnsDetails
  }

  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.leftMargin: Style.space(10)
    visible: root.groups.length === 0
    text: root.busy || !root.initialized ? "Looking for devices…" : "No devices. Plug in USB or turn on Wireless debugging."
    color: Util.alpha(Commons.Color.foreground, 0.6)
    Accessible.role: Accessible.StaticText
  }

  Repeater {
    model: root.groups
    delegate: ColumnLayout {
      required property var modelData
      required property int index
      Layout.fillWidth: true
      spacing: Style.space(6)
      PanelSeparator {
        Layout.fillWidth: true
        visible: index > 0
      }
      PanelSectionHeader {
        Layout.fillWidth: true
        Layout.leftMargin: Style.space(10)
        text: modelData.title
      }
      Repeater {
        model: modelData.rows
        delegate: DeviceRow {
          required property var modelData
          Layout.fillWidth: true
          row: modelData
          actionsBusy: root.actionsBusy
          onActivated: root.openDevice(modelData.serial)
          onActionRequested: kind => root.runRowAction(modelData, kind)
        }
      }
    }
  }

  PanelSeparator {
    Layout.fillWidth: true
    visible: root.groups.length > 0
  }
  CursorSurface {
    id: addRow
    objectName: "omadroidAddDevice"
    Layout.fillWidth: true
    implicitHeight: addContent.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: addMouse.containsMouse || activeFocus
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Add device"
    Accessible.onPressAction: root.addDevice()
    Keys.onReturnPressed: root.addDevice()
    Keys.onEnterPressed: root.addDevice()
    Keys.onSpacePressed: root.addDevice()
    MouseArea {
      id: addMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.addDevice()
    }
    RowLayout {
      id: addContent
      anchors {
        left: parent.left
        right: parent.right
        verticalCenter: parent.verticalCenter
        leftMargin: Style.space(10)
      }
      spacing: Style.space(10)
      Text {
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "+"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
      }
      Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        text: "Add device"
        color: addRow.hasCursor ? Commons.Color.foreground : Util.alpha(Commons.Color.foreground, 0.75)
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
    }
  }

  // A one-line, elided status message with an optional hover tooltip.
  component StatusLine: Label {
    property string tooltip: ""
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.leftMargin: Style.space(10)
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.NoWrap
    elide: Text.ElideRight
    Accessible.role: Accessible.StaticText
    HoverHandler {
      id: lineHover
    }
    PanelToolTip {
      // Elided messages show in full on hover.
      visible: lineHover.hovered && (parent.tooltip !== "" || parent.truncated)
      text: parent.tooltip !== "" ? parent.text + "\n" + parent.tooltip : parent.text
    }
  }
}
