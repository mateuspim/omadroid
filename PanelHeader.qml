import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DeviceListModel.js" as DeviceList

// Header shared by every view: optional back chevron, title with a dim
// subtitle, and compact icon buttons for refresh (home only) and settings.
// Discovery is push-based, so refresh is a small icon whose tooltip says how
// fresh the list is, not a big labelled button.
RowLayout {
  id: root
  property string title: "OmaDroid"
  property string subtitle: ""
  property bool showBack: false
  property bool showRefresh: false
  property bool showSettings: true
  // Discovery state for the refresh icon: it spins while busy.
  property bool busy: false
  property bool tracking: false
  property string updatedAt: ""
  property int intervalSec: 0
  // Opened state of the popup, so the spinner stops while hidden.
  property bool animate: true
  // The first tab stop, for KeyboardPanel.focusTarget.
  readonly property Item firstFocus: showBack ? backButton : showRefresh ? refreshButton : settingsButton
  signal back
  signal refresh
  signal settings

  spacing: Style.space(8)

  HeaderIcon {
    id: backButton
    visible: root.showBack
    iconText: "‹"
    iconSize: Style.font.heading
    tooltipText: "Back (Esc)"
    Accessible.name: "Back"
    onClicked: root.back()
  }
  ColumnLayout {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    spacing: Style.space(1)
    Label {
      Layout.fillWidth: true
      text: root.title
      font.bold: true
      font.pixelSize: Style.font.title
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
      Accessible.role: Accessible.Heading
    }
    Label {
      Layout.fillWidth: true
      visible: root.subtitle !== ""
      text: root.subtitle
      color: Util.alpha(Commons.Color.foreground, 0.6)
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
  }
  HeaderIcon {
    id: refreshButton
    visible: root.showRefresh
    iconText: "󰑐"
    // Only the glyph turns (Button spins its icon, not its hover square).
    iconSpinning: root.busy && root.animate
    tooltipText: DeviceList.refreshTooltip({ busy: root.busy, tracking: root.tracking, updatedAt: root.updatedAt, intervalSec: root.intervalSec })
    Accessible.name: root.busy ? "Scanning for devices" : "Refresh devices"
    // Stays enabled while scanning: a disabled Button dims, and the spin is the feedback.
    onClicked: if (!root.busy) root.refresh()
  }
  HeaderIcon {
    id: settingsButton
    visible: root.showSettings
    iconText: "󰒓"
    tooltipText: "Settings"
    Accessible.name: "Settings"
    onClicked: root.settings()
  }

  // Square, borderless icon button. Ui Button rather than PanelActionButton
  // because only Button can spin its glyph without turning its background.
  component HeaderIcon: Button {
    focusable: true
    iconSize: Style.font.title
    implicitWidth: Style.space(28)
    implicitHeight: Style.space(28)
    Layout.alignment: Qt.AlignVCenter
    Accessible.role: Accessible.Button
  }
}
