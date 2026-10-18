import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui
import "DeviceListModel.js" as DeviceList

// The bar widget and its popup. The popup is a small router: home (device
// list) → a device's page, plus Add device and Settings. One MirrorSession is
// shared by the session banner and every device page.
Panel {
  id: root
  moduleName: "pym.omadroid"
  ipcTarget: "pym.omadroid"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  // "home" | "device" | "add" | "settings"
  property string view: "home"
  property string deviceSerial: ""
  // Remembered across devices, so reopening a page lands where you were.
  property string deviceSection: "mirror"
  // Shown on home after the opened device disappeared.
  property string notice: ""
  readonly property var discovery: discoveryConsumer.discovery
  readonly property var currentDevice: discovery.rows.find(row => row.serial === root.deviceSerial) || null
  readonly property var sessionDevice: discovery.rows.find(row => row.serial === mirrorSession.sessionSerial) || null
  readonly property string sessionKind: mirrorSession.sessionType === "webcam" ? "webcam" : mirrorSession.sessionAudioOnly ? "audio" : "mirror"
  property string missingTools: ""
  readonly property string sessionScript: decodeURIComponent(Qt.resolvedUrl("session.sh").toString().replace(/^file:\/\//, ""))

  Component.onCompleted: prerequisites.start(["bash", sessionScript, "check"], 3)
  // Rechecked on open only while something is missing, so installing a tool
  // is noticed without spawning the check on every open.
  Command {
    id: prerequisites
    onFinished: (code, output, error) => root.missingTools = code === 0 ? output.trim().split("\n").filter(Boolean).join(", ") : "adb, scrcpy, foot or an Omarchy default terminal"
  }

  DiscoveryConsumer {
    id: discoveryConsumer
    shell: root.bar ? root.bar.shell : null
    pluginId: root.moduleName
  }

  Actions {
    id: actions
    discovery: discoveryConsumer.sharedDiscovery
  }

  MirrorSession {
    id: mirrorSession
    missingTools: root.missingTools
    wakeOnLaunch: discovery.preferences.wakeOnLaunch
    unlockOnLaunch: discovery.preferences.unlockOnLaunch
  }

  function go(next, serial) {
    if (view === "add" && next !== "add") {
      addDevice.clearCode();
      addDevice.cancel();
    }
    if (serial !== undefined)
      deviceSerial = serial;
    notice = "";
    view = next;
    if (pageScroll.contentItem)
      pageScroll.contentItem.contentY = 0;
  }
  function back() {
    go("home");
  }
  function stopSession() {
    mirrorSession.stop();
  }
  function openSession() {
    deviceSection = mirrorSession.sessionType === "webcam" ? "webcam" : "mirror";
    go("device", mirrorSession.sessionSerial);
  }
  // The quick actions toggle: a session of that kind here stops, otherwise
  // the Mirror form launches with its saved profile.
  function mirrorAction(serial, audioOnly) {
    var kind = audioOnly ? "audio" : "mirror";
    if (mirrorSession.busy && mirrorSession.sessionSerial === serial && root.sessionKind === kind) {
      mirrorSession.stop();
      return;
    }
    deviceSection = "mirror";
    Qt.callLater(() => {
      var section = devicePage.item ? devicePage.item.sectionItem : null;
      if (section && section.options)
        section.options.launch(audioOnly);
    });
  }
  // The overlay picks its device from lastTextTarget, so set it first.
  function openSendText(serial) {
    var shell = root.bar ? root.bar.shell : null;
    if (!shell || typeof shell.toggle !== "function")
      return;
    discoveryConsumer.setPreference("lastTextTarget", serial);
    root.close();
    shell.toggle(root.moduleName, "");
  }

  onOpenedChanged: {
    discoveryConsumer.holdMdns(opened);
    if (opened) {
      if (root.missingTools && !prerequisites.busy)
        prerequisites.start(["bash", sessionScript, "check"], 3);
      discoveryConsumer.refresh();
      mirrorSession.refreshSession();
    } else {
      addDevice.clearCode();
      // Wireless discovery stops with the popup, so the code could no longer pair.
      addDevice.cancel();
    }
  }
  onCurrentDeviceChanged: {
    if (view === "device" && currentDevice === null && discovery.initialized) {
      go("home");
      notice = "That device is no longer connected.";
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "OmaDroid · " + discovery.readyCount + " ready" + (mirrorSession.sessionPid > 0 ? " · " + mirrorSession.sessionTitle + " active" : "") + (root.missingTools ? " · Missing: " + root.missingTools : "") + (discovery.mdnsLevel === "error" ? " · wireless discovery unavailable" : "")
    iconComponent: Component {
      Item {
        DroidPromptIcon {
          anchors.centerIn: parent
          color: discovery.devicesError || root.missingTools ? Color.urgent : root.barForeground
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
        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          visible: mirrorSession.sessionPid > 0
          text: mirrorSession.sessionType === "webcam" ? "●" : "▶"
          color: Color.accent
          font.pixelSize: Style.font.caption
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
    focusTarget: header.firstFocus

    ColumnLayout {
      id: popupLayout
      objectName: "omadroidPopup"
      anchors.fill: parent
      spacing: Style.space(10)
      // Esc steps back to the list first, then closes.
      Keys.onEscapePressed: root.view === "home" ? root.close() : root.back()
      Keys.onPressed: event => {
        if (event.key === Qt.Key_F5) {
          if (!discovery.busy)
            discoveryConsumer.refresh();
          event.accepted = true;
        }
      }
      PanelHeader {
        id: header
        Layout.fillWidth: true
        // The device page names the device in its hero, so the header is a breadcrumb.
        title: root.view === "device" ? "Devices" : root.view === "add" ? "Add device" : root.view === "settings" ? "Settings" : "OmaDroid"
        subtitle: root.view === "home" ? DeviceList.homeSubtitle(discovery.rows) : ""
        showBack: root.view !== "home"
        showRefresh: root.view === "home"
        showSettings: root.view !== "settings"
        busy: discovery.busy
        tracking: discovery.tracking
        updatedAt: discovery.updatedAt
        intervalSec: discovery.intervalSec
        animate: root.opened
        onBack: root.back()
        onRefresh: discoveryConsumer.refresh()
        onSettings: root.go("settings")
      }
      Label {
        Layout.fillWidth: true
        visible: root.missingTools !== ""
        text: "⚠ Missing: " + root.missingTools
        color: Color.urgent
        elide: Text.ElideRight
      }
      SessionBanner {
        Layout.fillWidth: true
        active: mirrorSession.busy
        kind: root.sessionKind
        deviceName: root.sessionDevice ? root.sessionDevice.name : mirrorSession.sessionSerial
        stopping: mirrorSession.stopping
        onOpen: root.openSession()
        onStop: root.stopSession()
      }
      Controls.ScrollView {
        id: pageScroll
        objectName: "omadroidScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: pageContent.implicitHeight
        contentWidth: availableWidth
        clip: true
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        ColumnLayout {
          id: pageContent
          width: pageScroll.availableWidth
          spacing: Style.space(10)
          Label {
            Layout.fillWidth: true
            visible: root.view === "home" && root.notice !== ""
            text: root.notice
            color: Util.alpha(Color.foreground, 0.7)
            elide: Text.ElideRight
          }
          DeviceList {
            objectName: "omadroidDeviceList"
            Layout.fillWidth: true
            visible: root.view === "home"
            rows: discovery.rows
            actions: actions
            busy: discovery.busy
            initialized: discovery.initialized
            devicesError: discovery.devicesError
            mdnsError: discovery.mdnsError
            mdnsLevel: discovery.mdnsLevel
            mdnsDetails: discovery.mdnsDetails
            onOpenDevice: serial => root.go("device", serial)
            onAddDevice: root.go("add")
            onPairDevice: row => {
              root.go("add");
              addDevice.beginPair(row, discovery.rows, true);
            }
          }
          Loader {
            id: devicePage
            Layout.fillWidth: true
            // Room for the scrollbar, which is drawn over the page's right edge.
            Layout.rightMargin: Style.space(14)
            active: root.view === "device" && root.currentDevice !== null
            visible: active
            sourceComponent: DevicePage {
              objectName: "omadroidDevicePage"
              device: root.currentDevice
              actions: actions
              panelOpen: root.opened
              section: root.deviceSection
              onSectionChanged: root.deviceSection = section
              scrollView: pageScroll.contentItem
              sessionType: mirrorSession.busy && mirrorSession.sessionSerial === root.deviceSerial ? root.sessionKind : ""
              sessionBusy: mirrorSession.busy
              mirrorSection: mirrorComponent
              webcamSection: webcamComponent
              onMirrorRequested: serial => root.mirrorAction(serial, false)
              onAudioRequested: serial => root.mirrorAction(serial, true)
              onSendTextRequested: serial => root.openSendText(serial)
            }
          }
          AddDevicePage {
            id: addDevice
            Layout.fillWidth: true
            visible: root.view === "add"
            actions: actions
            onDone: root.go("home")
          }
          SettingsPane {
            Layout.fillWidth: true
            visible: root.view === "settings"
            consumer: discoveryConsumer
          }
        }
      }
    }
  }

  // DevicePage also binds device and panelOpen once loaded.
  Component {
    id: mirrorComponent
    MirrorSection {
      serial: root.deviceSerial
      session: mirrorSession
      devices: discovery.devices
      onShowSessionRequested: root.openSession()
    }
  }
  Component {
    id: webcamComponent
    WebcamSection {
      serial: root.deviceSerial
      session: mirrorSession
      devices: discovery.devices
      onShowSessionRequested: root.openSession()
    }
  }
}
