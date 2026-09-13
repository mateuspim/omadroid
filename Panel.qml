import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "pym.droidlink"
  ipcTarget: "pym.droidlink"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property string page: "devices"
  readonly property var discovery: discoveryConsumer.discovery

  DiscoveryConsumer {
    id: discoveryConsumer
    shell: root.bar ? root.bar.shell : null
    pluginId: root.moduleName
    intervalSec: Number(root.setting("refreshIntervalSec", 15)) || 15
  }

  function refreshDiscovery() {
    discoveryConsumer.refresh();
  }

  Actions {
    id: actions
    discovery: discoveryConsumer.sharedDiscovery
  }
  onOpenedChanged: {
    if (opened)
      root.refreshDiscovery();
    else
      connectionForm.clearCode();
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "DroidLink · " + discovery.readyCount + " ready" + (discovery.mdnsError ? " · wireless discovery unavailable" : "")
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰄜"
          color: discovery.devicesError ? Color.urgent : root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }
        Text {
          anchors {
            right: parent.right
            bottom: parent.bottom
          }
          visible: discovery.readyCount > 0
          text: discovery.readyCount > 9 ? "9+" : discovery.readyCount
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
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
    contentWidth: fittedContentWidth(Style.space(460))
    contentHeight: fittedContentHeight(popupLayout.implicitHeight, Style.space(650))
    focusTarget: refreshButton

    ColumnLayout {
      id: popupLayout
      objectName: "droidlinkPopup"
      anchors.fill: parent
      spacing: Style.space(12)
      Keys.onEscapePressed: root.close()
      Keys.onPressed: event => {
        if (event.key === Qt.Key_F5) {
          if (!discovery.busy)
            root.refreshDiscovery();
          event.accepted = true;
        }
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(12)
        ColumnLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: Style.space(3)
          Label {
            Layout.fillWidth: true
            text: "DroidLink"
            font.bold: true
            font.pixelSize: Style.font.title
          }
          Label {
            Layout.fillWidth: true
            text: discovery.readyCount + " ready · USB & wireless ADB"
            color: Util.alpha(Color.foreground, 0.7)
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
        }
        Button {
          id: refreshButton
          // Reserve the longer label's width so scanning never shifts the header.
          Layout.minimumWidth: Math.max(Style.space(128), refreshLabelMetrics.advanceWidth + horizontalPadding * 2 + iconSize + Style.spacing.controlGap + Style.space(4))
          Layout.minimumHeight: Style.space(36)
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
          text: discovery.busy ? "Scanning…" : "Refresh"
          iconText: "↻"
          iconSpinning: discovery.busy && root.opened
          bordered: true
          active: discovery.busy
          background: Util.alpha(Color.accent, 0.08)
          focusable: true
          enabled: !discovery.busy
          opacity: enabled ? 1 : 0.8
          tooltipText: "Refresh USB and wireless devices (F5)" + (discovery.updatedAt ? "\nLast scan: " + discovery.updatedAt : "")
          Accessible.name: discovery.busy ? "Scanning for devices" : "Refresh devices"
          onClicked: root.refreshDiscovery()

          TextMetrics {
            id: refreshLabelMetrics
            font.family: refreshButton.fontFamily
            font.pixelSize: refreshButton.fontSize
            text: "Scanning…"
          }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Repeater {
          model: [
            {
              key: "devices",
              label: "Devices"
            },
            {
              key: "wireless",
              label: "Wireless"
            },
            {
              key: "mirror",
              label: "Mirror"
            }
          ]
          delegate: ActionButton {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: modelData.label
            selected: root.page === modelData.key
            onClicked: root.page = modelData.key
          }
        }
      }
      Item {
        id: pageHost
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: root.page === "mirror" ? scrcpyPane.implicitHeight : pageContent.implicitHeight

        Controls.ScrollView {
          id: deviceScroll
          objectName: "droidlinkScroll"
          anchors.fill: parent
          visible: root.page !== "mirror"
          contentWidth: availableWidth
          clip: true
          Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
          ColumnLayout {
            id: pageContent
            width: deviceScroll.availableWidth
            spacing: Style.space(12)
          Label {
            Layout.fillWidth: true
            visible: root.page === "devices" && discovery.devicesError !== ""
            text: "ADB: " + discovery.devicesError
            color: Color.urgent
          }
          Label {
            Layout.fillWidth: true
            visible: root.page !== "mirror" && discovery.mdnsError !== ""
            text: "Wireless discovery: " + discovery.mdnsError + "\nYou can still connect or pair manually in Wireless."
            color: Color.urgent
          }
          Label {
            Layout.fillWidth: true
            visible: root.page === "devices" && discovery.initialized && discovery.rows.length === 0
            text: "No devices found\nConnect a USB cable and enable USB debugging, or enable Wireless debugging on Android on the same network."
            lineHeight: 1.3
          }
          Label {
            Layout.fillWidth: true
            visible: root.page !== "mirror" && actions.message !== ""
            text: actions.message
            color: actions.failed ? Color.urgent : Color.accent
            Accessible.role: Accessible.StaticText
          }
          Repeater {
            model: root.page === "devices" ? discovery.rows : []
            delegate: Rectangle {
              required property var modelData
              Layout.fillWidth: true
              implicitHeight: deviceCardContent.implicitHeight + Style.space(24)
              radius: Style.cornerRadius
              color: Util.alpha(Color.foreground, 0.04)
              border.color: Util.alpha(Color.foreground, 0.14)
              ColumnLayout {
                id: deviceCardContent
                anchors {
                  left: parent.left
                  right: parent.right
                  top: parent.top
                  margins: Style.space(12)
                }
                spacing: Style.space(5)
                Label {
                  Layout.fillWidth: true
                  text: modelData.name
                  font.bold: true
                }
                Label {
                  Layout.fillWidth: true
                  text: modelData.transport + " · " + Model.statusLabel(modelData.status)
                  color: modelData.status === "device" ? Color.accent : Util.alpha(Color.foreground, 0.7)
                }
                Label {
                  Layout.fillWidth: true
                  text: (modelData.source === "mdns" ? "Service: " : "Serial: ") + modelData.serial
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                }
                Label {
                  Layout.fillWidth: true
                  visible: modelData.endpoint !== ""
                  text: modelData.endpoint
                  color: Util.alpha(Color.foreground, 0.7)
                }
                Label {
                  Layout.fillWidth: true
                  visible: text !== ""
                  text: Model.statusHint(modelData)
                  font.pixelSize: Style.font.bodySmall
                  color: Util.alpha(Color.foreground, 0.7)
                }
                RowLayout {
                  Layout.fillWidth: true
                  ActionButton {
                    text: "Mirror…"
                    visible: modelData.status === "device"
                    enabled: !scrcpyPane.busy
                    onClicked: {
                      scrcpyPane.chooseDevice(modelData.serial);
                      root.page = "mirror";
                    }
                  }
                  ActionButton {
                    text: "Connect"
                    visible: !modelData.pair && (modelData.source === "mdns" || (modelData.status === "offline" && modelData.endpoint !== ""))
                    enabled: !actions.busy
                    onClicked: actions.run("connect", modelData.endpoint, "")
                  }
                  ActionButton {
                    text: "Pair…"
                    visible: modelData.pair || (modelData.source === "mdns" && modelData.endpoint !== "")
                    enabled: !actions.busy
                    tooltipText: modelData.pair ? "Use this advertised pairing port" : "Reuse this host and enter Android's separate pairing port"
                    onClicked: {
                      root.page = "wireless";
                      connectionForm.beginPair(modelData, discovery.rows);
                    }
                  }
                  ActionButton {
                    text: "Disconnect"
                    visible: modelData.source === "adb" && modelData.transport === "Wireless"
                    enabled: !actions.busy && !(scrcpyPane.busy && scrcpyPane.sessionSerial === modelData.serial)
                    onClicked: actions.run("disconnect", modelData.serial, "")
                  }
                }
                Label {
                  Layout.fillWidth: true
                  visible: modelData.transport === "USB"
                  text: "Unplug USB to disconnect."
                  color: Util.alpha(Color.foreground, 0.7)
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
          Label {
            Layout.fillWidth: true
            visible: root.page === "devices"
            text: discovery.busy ? "Discovering devices…" : "Last scan " + (discovery.updatedAt || "pending") + " · every " + discovery.intervalSec + "s"
            font.pixelSize: Style.font.bodySmall
            color: Util.alpha(Color.foreground, 0.7)
          }
          ConnectionForm {
            id: connectionForm
            Layout.fillWidth: true
            visible: root.page === "wireless"
            actions: actions
          }
          }
        }
        ScrcpyPane {
          id: scrcpyPane
          objectName: "droidlinkScrcpy"
          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
          }
          visible: root.page === "mirror"
          devices: discovery.devices
        }
      }
    }
  }
  onPageChanged: {
    if (page !== "wireless")
      connectionForm.clearCode();
    if (deviceScroll.contentItem)
      deviceScroll.contentItem.contentY = 0;
  }
}
