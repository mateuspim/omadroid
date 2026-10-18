import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "DevicePage.js" as DevicePage
import "DeviceActions.js" as DeviceActions

// One device's page: hero, quick actions, then the Mirror · Webcam · Sound ·
// Info sections. Mirror and Webcam come from the caller as Components, so this
// page owns no session logic; it only asks for one through its signals.
ColumnLayout {
  id: root
  // The discovery row: serial, name, model, transport, status, info, endpoint, source…
  required property var device
  // Actions.qml, for Go wireless and Disconnect.
  property var actions: null
  property bool panelOpen: true
  // "mirror" | "webcam" | "sound" | "info"; the caller may bind and remember it.
  property string section: "mirror"
  // Loaded while their section is shown. If the loaded item declares any of
  // `device`, `serial`, `actions` or `panelOpen`, the page binds them.
  property Component mirrorSection: null
  property Component webcamSection: null
  // The Flickable the page scrolls in, so sliders hand it the wheel.
  property var scrollView: null
  // This device's running session ("mirror" | "audio" | "webcam" | ""), and
  // whether any session is starting or stopping.
  property string sessionType: ""
  property bool sessionBusy: false
  signal mirrorRequested(string serial)
  signal audioRequested(string serial)
  signal sendTextRequested(string serial)

  // Shared by the quick actions and the Info section's unlock PIN.
  readonly property alias powerState: devicePower
  // The loaded section, so the panel can launch through the Mirror form's profile.
  readonly property alias sectionItem: sectionLoader.item
  readonly property string serial: device ? device.serial : ""
  readonly property bool ready: device !== null && device.status === "device"
  readonly property string shownSection: DevicePage.pageSection(section)
  readonly property var quickActions: DeviceActions.deviceActions(device, {
    keepAwake: devicePower.keepAwake,
    keepAwakeRunning: devicePower.power !== null && devicePower.power.running,
    powerKnown: devicePower.power !== null,
    powerBusy: devicePower.busy,
    canUnlock: devicePower.canUnlock,
    actionsBusy: actions !== null && actions.busy,
    sessionBusy: sessionBusy,
    sessionType: sessionType
  })
  // One handler per DeviceActions registry key.
  readonly property var actionHandlers: ({
    mirror: () => root.mirrorRequested(root.serial),
    audio: () => root.audioRequested(root.serial),
    wake: () => devicePower.wake(),
    lock: () => devicePower.lock(),
    keepAwake: () => devicePower.toggleKeepAwake(),
    sendText: () => root.sendTextRequested(root.serial),
    goWireless: () => root.actions.goWireless(root.serial),
    disconnect: () => root.actions.run("disconnect", root.serial, "")
  })
  spacing: Style.space(12)

  function runAction(key) {
    var handler = actionHandlers[key];
    if (!handler)
      throw new Error("No handler for device action '" + key + "'; expected one of " + Object.keys(actionHandlers).join(", "));
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
  function bindSectionItem(item) {
    var bindings = {
      device: () => root.device,
      serial: () => root.serial,
      actions: () => root.actions,
      panelOpen: () => root.panelOpen
    };
    for (var name in bindings) {
      if (name in item)
        item[name] = Qt.binding(bindings[name]);
    }
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
          color: root.ready ? Color.accent : Util.alpha(Color.foreground, 0.5)
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
      color: Util.alpha(Color.foreground, 0.7)
    }
  }

  DeviceQuickActions {
    objectName: "deviceQuickActions"
    Layout.fillWidth: true
    visible: root.quickActions.length > 0
    entries: root.quickActions
    onTriggered: key => root.runAction(key)
  }
  Repeater {
    model: root.feedback()
    delegate: Label {
      required property var modelData
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: (modelData.failed ? "⚠ " : "") + modelData.text
      wrapMode: Text.WordWrap
      color: modelData.failed ? Color.urgent : Util.alpha(Color.foreground, 0.7)
    }
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
    sourceComponent: ({
        mirror: root.mirrorSection || placeholder,
        webcam: root.webcamSection || placeholder,
        sound: soundSection,
        info: infoSection
      })[root.shownSection]
    onLoaded: root.bindSectionItem(item)
  }

  Component {
    id: placeholder
    Label {
      objectName: "deviceSectionPlaceholder"
      text: (root.shownSection === "webcam" ? "Webcam" : "Mirror") + " options will appear here."
      color: Util.alpha(Color.foreground, 0.7)
    }
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
