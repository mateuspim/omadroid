import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
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
  property var pendingPairFallback: null
  // The device card whose details are expanded; kept here because scans rebuild the cards.
  property string detailsSerial: ""
  readonly property var discovery: discoveryConsumer.discovery
  property string missingTools: ""
  readonly property string sessionScript: decodeURIComponent(Qt.resolvedUrl("session.sh").toString().replace(/^file:\/\//, ""))

  Component.onCompleted: prerequisites.start(["bash", sessionScript, "check"], 3)
  Command {
    id: prerequisites
    onFinished: (code, output, error) => root.missingTools = code === 0 ? output.trim().split("\n").filter(Boolean).join(", ") : "adb, scrcpy, Omarchy default terminal"
  }

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
    onChanged: {
      var row = root.pendingPairFallback;
      root.pendingPairFallback = null;
      if (!Model.needsPairingFallback(row, actions.failed))
        return;
      root.page = "wireless";
      connectionForm.beginPair(row, discovery.rows, true);
    }
  }
  onOpenedChanged: {
    discoveryConsumer.holdMdns(opened);
    if (opened) {
      if (!prerequisites.busy)
        prerequisites.start(["bash", sessionScript, "check"], 3);
      root.refreshDiscovery();
    } else
      connectionForm.clearCode();
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "DroidLink · " + discovery.readyCount + " ready" + (root.missingTools ? " · Missing: " + root.missingTools : "") + (discovery.mdnsLevel === "error" ? " · wireless discovery unavailable" : "")
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰄜"
          color: discovery.devicesError || root.missingTools ? Color.urgent : root.barForeground
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
      Label {
        Layout.fillWidth: true
        visible: root.missingTools !== ""
        text: "⚠ Missing tools: " + root.missingTools + ". Install them to use DroidLink mirroring."
        color: Color.urgent
        wrapMode: Text.WordWrap
      }
      RowLayout {
        Layout.fillWidth: true
        Accessible.role: Accessible.PageTabList
        Accessible.name: "DroidLink pages"
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
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.label
            Accessible.selectable: true
            Accessible.selected: selected
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
            text: "⚠ ADB: " + discovery.devicesError
            color: Color.urgent
          }
          // A warning (a device didn't answer) is muted; a hard failure is urgent.
          // The raw Avahi output stays in the tooltip.
          Label {
            Layout.fillWidth: true
            visible: root.page !== "mirror" && discovery.mdnsError !== ""
            text: discovery.mdnsLevel === "error" ? "⚠ Wireless discovery: " + discovery.mdnsError + "\nYou can still connect or pair manually in Wireless." : discovery.mdnsError
            color: discovery.mdnsLevel === "error" ? Color.urgent : Util.alpha(Color.foreground, 0.7)
            lineHeight: 1.3
            Controls.ToolTip.text: discovery.mdnsDetails
            Controls.ToolTip.visible: mdnsHover.hovered && discovery.mdnsDetails !== ""
            HoverHandler {
              id: mdnsHover
            }
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
            text: (actions.failed ? "⚠ " : "") + actions.message
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
                  text: (modelData.model && modelData.model !== modelData.name ? modelData.model + " · " : "") + modelData.transport + " · " + Model.statusLabel(modelData.status)
                  color: modelData.status === "device" ? Color.accent : Util.alpha(Color.foreground, 0.7)
                }
                Label {
                  Layout.fillWidth: true
                  visible: text !== "" && root.detailsSerial !== modelData.serial
                  text: Model.deviceSummary(modelData.info)
                  wrapMode: Text.WordWrap
                }
                GridLayout {
                  Layout.fillWidth: true
                  visible: root.detailsSerial === modelData.serial
                  columns: 2
                  columnSpacing: Style.space(12)
                  rowSpacing: Style.space(3)
                  Repeater {
                    model: root.detailsSerial === modelData.serial ? Model.deviceDetails(modelData.info).reduce((cells, row) => cells.concat([row.label, row.value]), []) : []
                    delegate: Label {
                      required property var modelData
                      required property int index
                      Layout.fillWidth: index % 2 === 1
                      Layout.alignment: Qt.AlignTop
                      text: modelData
                      wrapMode: index % 2 === 1 ? Text.WordWrap : Text.NoWrap
                      color: index % 2 === 0 ? Util.alpha(Color.foreground, 0.7) : Color.foreground
                    }
                  }
                }
                Label {
                  Layout.fillWidth: true
                  text: (modelData.source === "mdns" ? "Service: " : "Serial: ") + modelData.serial
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                }
                Label {
                  Layout.fillWidth: true
                  visible: modelData.endpoint !== "" && modelData.endpoint !== modelData.serial
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
                    text: root.detailsSerial === modelData.serial ? "Hide details" : "Details"
                    visible: Model.deviceDetails(modelData.info).length > 0
                    selected: root.detailsSerial === modelData.serial
                    tooltipText: "Battery, storage, memory and screen, read every minute while this popup is open"
                    onClicked: root.detailsSerial = root.detailsSerial === modelData.serial ? "" : modelData.serial
                  }
                  ActionButton {
                    text: "Connect"
                    visible: !modelData.pair && (modelData.source === "mdns" || (modelData.status === "offline" && modelData.endpoint !== ""))
                    enabled: !actions.busy
                    tooltipText: modelData.source === "mdns" ? "Connect if already paired; open Pair automatically if it fails" : "Reconnect this wireless endpoint"
                    onClicked: {
                      root.pendingPairFallback = modelData.source === "mdns" ? modelData : null;
                      if (!actions.run("connect", modelData.endpoint, ""))
                        root.pendingPairFallback = null;
                    }
                  }
                  ActionButton {
                    text: "Pair…"
                    visible: modelData.pair
                    enabled: !actions.busy
                    tooltipText: "Use this advertised pairing port"
                    onClicked: {
                      root.page = "wireless";
                      connectionForm.beginPair(modelData, discovery.rows, true);
                    }
                  }
                  ActionButton {
                    text: "Disconnect"
                    visible: modelData.source === "adb" && modelData.transport === "Wireless"
                    enabled: !actions.busy && !(scrcpyPane.busy && scrcpyPane.sessionSerial === modelData.serial)
                    onClicked: actions.run("disconnect", modelData.serial, "")
                  }
                }
              }
            }
          }
          Label {
            Layout.fillWidth: true
            visible: root.page === "devices" && discovery.rows.some(row => row.transport === "USB")
            text: "To disconnect a USB device, unplug its cable."
            color: Util.alpha(Color.foreground, 0.7)
            font.pixelSize: Style.font.bodySmall
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
        // Session controls make this page taller than the popup's height cap,
        // so it scrolls like the device pages instead of overflowing the card.
        Controls.ScrollView {
          id: mirrorScroll
          objectName: "droidlinkMirrorScroll"
          anchors.fill: parent
          visible: root.page === "mirror"
          contentWidth: availableWidth
          clip: true
          Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
          ScrcpyPane {
            id: scrcpyPane
            objectName: "droidlinkScrcpy"
            width: mirrorScroll.availableWidth
            devices: discovery.devices
            missingTools: root.missingTools
            panelOpen: root.opened
          }
        }
      }
    }
  }
  onPageChanged: {
    if (page !== "wireless")
      connectionForm.clearCode();
    for (const scroll of [deviceScroll, mirrorScroll]) {
      if (scroll.contentItem)
        scroll.contentItem.contentY = 0;
    }
  }
}
