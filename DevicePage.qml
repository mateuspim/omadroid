import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "DevicePage.js" as DevicePage
import "DeviceActions.js" as DeviceActions

// One device's page: hero, the session cards (Mirror · Audio · Webcam) with
// their options and the running session's controls, a compact row of device
// controls, then the Sound · Info sections.
ColumnLayout {
  id: root
  // The discovery row: serial, name, model, transport, status, info, endpoint, source…
  required property var device
  // The machine's one scrcpy session (MirrorSession), shared with the banner.
  required property var session
  // Every discovery row, so a session on another device can be named.
  property var devices: []
  // Actions.qml, for Go wireless and Disconnect.
  property var actions: null
  property bool panelOpen: true
  // "sound" | "info"; the caller may bind and remember it.
  property string section: "sound"
  // The Flickable the page scrolls in, so sliders hand it the wheel.
  property var scrollView: null
  signal sendTextRequested(string serial)

  // Shared by the controls and the Info section's unlock PIN.
  readonly property alias powerState: devicePower
  // The session cards and their option forms.
  readonly property alias sessions: deviceSessions
  readonly property string serial: device ? device.serial : ""
  readonly property bool ready: device !== null && device.status === "device"
  readonly property string shownSection: DevicePage.pageSection(section)
  readonly property var controls: DeviceActions.deviceControls(device, {
    keepAwake: devicePower.keepAwake,
    keepAwakeRunning: devicePower.power !== null && devicePower.power.running,
    powerKnown: devicePower.power !== null,
    powerBusy: devicePower.busy,
    canUnlock: devicePower.canUnlock,
    actionsBusy: actions !== null && actions.busy,
    sessionType: deviceSessions.sessionHere ? deviceSessions.sessionKind : ""
  })
  // One handler per DeviceActions control registry key.
  readonly property var controlHandlers: ({
    wake: () => devicePower.wake(),
    lock: () => devicePower.lock(),
    keepAwake: () => devicePower.toggleKeepAwake(),
    sendText: () => root.sendTextRequested(root.serial),
    goWireless: () => root.actions.goWireless(root.serial),
    disconnect: () => root.actions.run("disconnect", root.serial, "")
  })
  spacing: Style.space(12)

  function runControl(key) {
    var handler = controlHandlers[key];
    if (!handler)
      throw new Error("No handler for device control '" + key + "'; expected one of " + Object.keys(controlHandlers).join(", "));
    handler();
  }
  // Results of this device's own commands; Actions.qml is shared by every page.
  function feedback() {
    var lines = [];
    if (devicePower.message)
      lines.push({ text: devicePower.message, failed: devicePower.failed });
    if (actions && actions.message && actions.target === serial)
      lines.push({ text: actions.message, failed: actions.failed });
    return lines;
  }

  DevicePowerState {
    id: devicePower
    serial: root.serial
    ready: root.ready
    panelOpen: root.panelOpen
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.space(4)
    PanelHero {
      id: hero
      Layout.fillWidth: true
      title: root.device.name || root.serial
      meta: DevicePage.heroMeta(root.device)
      iconComponent: Component {
        Text {
          width: Style.font.display
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "󰄜"
          color: root.ready ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.display
        }
      }
    }
    Label {
      objectName: "deviceHeroStats"
      // Lines up under the hero's labels, which start after its icon.
      Layout.leftMargin: Style.font.display + Style.space(14)
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      visible: text !== ""
      text: root.ready ? DevicePage.heroStats(root.device.info) : Model.statusHint(root.device)
      wrapMode: root.ready ? Text.NoWrap : Text.WordWrap
      elide: Text.ElideRight
      color: Util.alpha(Commons.Color.foreground, 0.7)
    }
  }

  DeviceSessions {
    id: deviceSessions
    objectName: "deviceSessions"
    Layout.fillWidth: true
    visible: root.ready
    serial: root.serial
    device: root.device
    devices: root.devices
    session: root.session
    panelOpen: root.panelOpen
  }
  DeviceControls {
    objectName: "deviceControls"
    Layout.fillWidth: true
    visible: root.controls.length > 0
    entries: root.controls
    onTriggered: key => root.runControl(key)
  }
  Repeater {
    model: root.feedback()
    delegate: Label {
      required property var modelData
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: (modelData.failed ? "⚠ " : "") + modelData.text
      wrapMode: Text.WordWrap
      color: modelData.failed ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.7)
    }
  }

  PanelSeparator {
    Layout.fillWidth: true
    visible: root.ready
  }
  ButtonGroup {
    objectName: "deviceSections"
    Layout.fillWidth: true
    visible: root.ready
    spacing: Style.space(6)
    options: DevicePage.deviceSections()
    value: root.shownSection
    onChanged: value => root.section = value
  }
  Loader {
    id: sectionLoader
    objectName: "deviceSection"
    Layout.fillWidth: true
    visible: root.ready
    active: root.ready
    sourceComponent: root.shownSection === "info" ? infoSection : soundSection
  }

  Component {
    id: soundSection
    SoundPane {
      objectName: "omadroidSound"
      serial: root.serial
      active: root.panelOpen && root.ready
      scrollView: root.scrollView
    }
  }
  Component {
    id: infoSection
    DeviceInfoSection {
      device: root.device
      powerState: root.powerState
    }
  }
}
