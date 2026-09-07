import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "pym.droidlink"
  ipcTarget: "pym.droidlink"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Text {
        anchors.centerIn: parent
        text: "ADB"
        color: root.barForeground
        font.pixelSize: Style.fontSize(-2)
        font.bold: true
      }
    }
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(300)
    contentHeight: Style.space(96)

    Text {
      anchors.centerIn: parent
      text: "DroidLink\nDevice discovery is coming next."
      color: Color.foreground
      horizontalAlignment: Text.AlignHCenter
      lineHeight: 1.35
    }
  }
}
