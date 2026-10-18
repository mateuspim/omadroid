import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The Mirror and Webcam tabs until the device page replaces them: a device
// dropdown over MirrorSection or WebcamSection. The session is shared with
// the panel when it passes one; otherwise this pane runs its own instance.
// The forwarders below keep the panel and tests/Smoke.qml working.
ColumnLayout {
  id: root
  required property var devices
  property string pageMode: "mirror"
  signal requestPage(string page)
  property string selectedSerial: ""
  // Supplied by the panel, which runs `session.sh check` on open.
  property string missingTools: ""
  property bool panelOpen: true
  // Plugin settings: wake or unlock the device before scrcpy starts.
  property bool wakeOnLaunch: true
  property bool unlockOnLaunch: false
  property var session: ownSession
  property bool optionsExpanded: false
  property alias webcamPreview: webcamSection.previewOpen
  readonly property var activeSection: pageMode === "webcam" ? webcamSection : mirrorSection
  readonly property var mirrorOptions: mirrorSection.options
  readonly property var webcamOptions: webcamSection.options
  // Where the folded options start, so the panel can scroll them into view.
  readonly property real optionsTop: activeSection.y + activeSection.optionsTop
  readonly property var readyDevices: devices.filter(row => row.status === "device")
  readonly property var selectedDevice: devices.find(row => row.serial === selectedSerial) || null
  readonly property var deviceOptions: readyDevices.map(row => ({
        value: row.serial,
        label: row.name + " · " + row.transport + " · " + row.serial
      }))

  // Session state, read by the panel's bar icon and the smoke test.
  readonly property bool busy: session.busy
  readonly property int sessionPid: session.sessionPid
  readonly property string sessionSerial: session.sessionSerial
  readonly property string sessionType: session.sessionType
  readonly property string sessionSink: session.sessionSink
  readonly property string sessionRecording: session.sessionRecording
  readonly property var sessionArgs: session.sessionArgs
  readonly property bool restartPending: session.restartPending
  readonly property string message: session.message
  readonly property bool failed: session.failed
  readonly property var profile: mirrorOptions.profile
  readonly property bool webcamChanged: webcamOptions.webcamChanged
  spacing: Style.space(6)

  onReadyDevicesChanged: {
    // Preserve a vanished selection so unplugging cannot silently redirect a
    // launch to another phone. Only auto-select before any explicit choice.
    if (!selectedSerial && readyDevices.length)
      selectedSerial = readyDevices[0].serial;
  }
  onPanelOpenChanged: if (panelOpen)
    session.refreshSession()

  function chooseDevice(serial) {
    selectedSerial = serial;
  }
  function launch(audioOnly) {
    mirrorOptions.launch(audioOnly);
  }
  function stop() {
    session.stop();
  }
  function changeOption(key, value) {
    mirrorOptions.changeOption(key, value);
  }
  function selectProfile(name) {
    mirrorOptions.selectProfile(name);
  }
  function saveProfile(name) {
    mirrorOptions.saveProfile(name);
  }
  function launchWebcam() {
    webcamOptions.launchWebcam();
  }
  function applyWebcam() {
    webcamOptions.applyWebcam();
  }

  MirrorSession {
    id: ownSession
    missingTools: root.missingTools
    wakeOnLaunch: root.wakeOnLaunch
    unlockOnLaunch: root.unlockOnLaunch
  }
  // One fold state for both tabs, as before the split.
  Binding {
    target: mirrorSection
    property: "optionsExpanded"
    value: root.optionsExpanded
  }
  Binding {
    target: webcamSection
    property: "optionsExpanded"
    value: root.optionsExpanded
  }

  Dropdown {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    label: "Device"
    value: root.selectedSerial
    options: root.deviceOptions
    enabled: root.readyDevices.length > 0 && !root.activeSection.sessionHere
    Accessible.name: root.pageMode === "webcam" ? "Webcam device" : "Mirror device"
    onChanged: value => root.chooseDevice(value)
  }
  MirrorSection {
    id: mirrorSection
    Layout.fillWidth: true
    visible: root.pageMode !== "webcam"
    serial: root.selectedSerial
    device: root.selectedDevice
    devices: root.devices
    session: root.session
    panelOpen: root.panelOpen && root.pageMode !== "webcam"
    onOptionsExpandedChanged: root.optionsExpanded = optionsExpanded
    onShowSessionRequested: kind => root.requestPage(kind)
  }
  WebcamSection {
    id: webcamSection
    Layout.fillWidth: true
    visible: root.pageMode === "webcam"
    serial: root.selectedSerial
    device: root.selectedDevice
    devices: root.devices
    session: root.session
    panelOpen: root.panelOpen && root.pageMode === "webcam"
    onOptionsExpandedChanged: root.optionsExpanded = optionsExpanded
    onShowSessionRequested: kind => root.requestPage(kind)
  }
}
