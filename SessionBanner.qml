import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DeviceListModel.js" as DeviceList

// One-line banner under the header while a scrcpy session runs, on every
// view: click it to jump to that session's controls, ■ to stop it.
// Collapses to nothing when inactive so hosts can leave it in the layout.
Rectangle {
  id: root
  property bool active: false
  // "mirror", "webcam" or "audio".
  property string kind: "mirror"
  property string deviceName: ""
  property bool stopping: false
  // The kind a switch is waiting to start ("" = none); ■ then cancels it.
  property string switchingTo: ""
  signal open
  signal stop

  visible: active
  implicitHeight: active ? content.implicitHeight + Style.space(10) : 0
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.accent, bannerMouse.containsMouse || activeFocus ? 0.16 : 0.09)
  border.width: Style.spacing.hairline
  border.color: Util.alpha(Commons.Color.accent, 0.3)
  activeFocusOnTab: active
  Accessible.role: Accessible.Button
  Accessible.name: DeviceList.sessionBannerText(kind, deviceName) + (stopping ? ", stopping" : "")
  Accessible.onPressAction: root.open()
  Keys.onReturnPressed: root.open()
  Keys.onEnterPressed: root.open()
  Keys.onSpacePressed: root.open()
  Behavior on color {
    ColorAnimation {
      duration: 60
    }
  }

  MouseArea {
    id: bannerMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.open()
  }

  RowLayout {
    id: content
    anchors {
      left: parent.left
      right: parent.right
      verticalCenter: parent.verticalCenter
      leftMargin: Style.space(10)
      rightMargin: Style.space(4)
    }
    spacing: Style.space(8)
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: root.switchingTo ? DeviceList.switchBannerText(root.switchingTo) : root.stopping ? "Stopping " + root.deviceName + "…" : DeviceList.sessionBannerText(root.kind, root.deviceName)
      color: Commons.Color.accent
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    PanelActionButton {
      iconText: "■"
      fontSize: Style.font.bodySmall
      foreground: Commons.Color.accent
      hoverColor: Commons.Color.urgent
      enabled: !root.stopping || root.switchingTo !== ""
      tooltipText: root.switchingTo ? "Cancel the switch" : "Stop session"
      Accessible.role: Accessible.Button
      Accessible.name: "Stop session"
      onClicked: root.stop()
    }
  }
}
