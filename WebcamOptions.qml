import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtCore as Core
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Webcam.js" as Webcam
import "SettingsFile.js" as SettingsFile

// Webcam settings for one device: camera, quality, v4l2 output, the folded
// quality details and setup guidance when no v4l2loopback output exists. The
// device page's Webcam card starts it through launchWebcam(), and the
// running session's card applies changes through applyWebcam(). Settings are
// saved in omadroid.ini and shared by every device and widget.
//
// Public API
//   serial (required), session (required, MirrorSession), ready, panelOpen
//   (the popup is open: outputs are rescanned and settings reloaded then),
//   scanCameras (this form is on screen: the phone's cameras are read then;
//   defaults to panelOpen), webcam, cameras,
//   webcamSink, webcamOutputs, webcamIssue, webcamDetailsOpen, webcamChanged
//   launchWebcam(), applyWebcam(), setWebcam(changes, keepPreset),
//   applyPreset(name), refreshWebcamOutputs(), refreshCameras(),
//   copyWebcamCommands(), reloadWebcam()
//
// Usage:
//   WebcamOptions { serial: "USB123"; session: mirrorSession; ready: true; panelOpen: popup.opened }
ColumnLayout {
  id: root
  objectName: "omadroidWebcamOptions"
  required property string serial
  required property var session
  property bool ready: false
  property bool panelOpen: true
  // Reading cameras runs scrcpy on the phone, so a folded form doesn't ask.
  property bool scanCameras: panelOpen
  // Camera, quality and adjustments for the next webcam (Webcam.webcamSettings),
  // saved in omadroid.ini. Replaced whole by setWebcam() so bindings update.
  property var webcam: Webcam.webcamSettings("")
  // Each device's cameras (Webcam.parseCameraList), read once per serial.
  // A phone whose scan failed maps to [] (and its error), so it is not asked
  // again on every open; Refresh asks again.
  property var cameraCatalog: ({})
  property var cameraScanErrors: ({})
  readonly property string cameraScanError: cameraScanErrors[serial] || ""
  readonly property var cameras: cameraCatalog[serial] || null
  readonly property var currentCamera: Webcam.chosenCamera(cameras, webcam.camera)
  // Set when the camera list arrives mid-session; fitting then would change
  // the shown settings and offer an Apply nobody asked for.
  property bool fitPending: false
  property bool webcamDetailsOpen: false
  property string webcamSink: ""
  property var webcamOutputs: []
  property string webcamIssue: ""
  property string webcamScanError: ""
  readonly property bool webcamRunning: session.sessionType === "webcam" && session.sessionPid > 0
  // While a webcam runs, Apply keeps its phone and output, whatever this
  // form's device and output say.
  readonly property var nextWebcamArgs: {
    var target = webcamRunning ? session.sessionSerial : serial;
    var sink = webcamRunning ? session.sessionSink : webcamSink;
    try {
      return (webcamRunning || ready) && target && sink ? Webcam.webcamCommand(target, webcam, sink) : null;
    } catch (e) {
      return null;
    }
  }
  readonly property bool webcamChanged: webcamRunning && !session.stopping && session.sessionArgs.length > 0 && nextWebcamArgs !== null && JSON.stringify(nextWebcamArgs) !== JSON.stringify(session.sessionArgs)
  readonly property string webcamScript: decodeURIComponent(Qt.resolvedUrl("scripts/webcam-devices.sh").toString().replace(/^file:\/\//, ""))
  spacing: Style.space(6)

  Core.Settings {
    id: saved
    location: SettingsFile.omadroidIniUrl(Quickshell.env("XDG_CONFIG_HOME") || "", Quickshell.env("HOME"))
    property string webcamJson: ""
  }
  Component.onCompleted: {
    webcam = Webcam.webcamSettings(saved.webcamJson);
    refreshWebcamOutputs();
    Qt.callLater(scanCamerasIfNeeded);
  }
  onPanelOpenChanged: if (panelOpen) {
    reloadWebcam();
    refreshWebcamOutputs();
    Qt.callLater(scanCamerasIfNeeded);
  }
  onReadyChanged: Qt.callLater(scanCamerasIfNeeded)
  onScanCamerasChanged: Qt.callLater(scanCamerasIfNeeded)
  onSerialChanged: {
    Qt.callLater(scanCamerasIfNeeded);
    if (cameras && cameras.length)
      fitWebcamToCamera();
  }
  Connections {
    target: root.session
    function onWebcamArgsRead() {
      root.reloadWebcam();
    }
    function onSessionPidChanged() {
      if (root.session.sessionPid === 0 && root.fitPending) {
        root.fitPending = false;
        Qt.callLater(root.fitWebcamToCamera);
      }
    }
  }

  function refreshWebcamOutputs() {
    if (!webcamScan.busy)
      webcamScan.start(["bash", webcamScript, "list"], 3);
  }
  function copyWebcamCommands() {
    setupCard.copyCommands();
  }
  // Only a form on screen asks, once per device.
  function scanCamerasIfNeeded() {
    if (scanCameras && ready && !cameraCatalog[serial])
      refreshCameras();
  }
  function refreshCameras() {
    if (!ready || cameraScan.busy)
      return;
    cameraScan.serial = serial;
    cameraScan.start(["bash", webcamScript, "cameras", serial], 25);
  }
  // Every widget keeps its own copy; another monitor's widget may have
  // saved newer settings since.
  function reloadWebcam() {
    saved.sync();
    webcam = Webcam.webcamSettings(saved.value("webcamJson", saved.webcamJson));
  }
  // Example: setWebcam({ fps: "24" }) marks the quality preset Custom.
  function setWebcam(changes, keepPreset) {
    var next = Object.assign({}, webcam, changes);
    if (!keepPreset)
      next.preset = "custom";
    webcam = next;
    // Written through at once: the property alone is saved later, and other
    // monitors' widgets read the file when they see this webcam start.
    saved.webcamJson = JSON.stringify(next);
    saved.setValue("webcamJson", saved.webcamJson);
    saved.sync();
  }
  function applyPreset(name) {
    var preset = Webcam.webcamPresets().find(p => p.value === name);
    if (preset)
      setWebcam({
        preset: name,
        size: Webcam.pickCameraSize(currentCamera, preset.size),
        fps: Webcam.pickCameraFps(currentCamera, preset.fps),
        bitRate: preset.bitRate,
        codec: preset.codec
      }, true);
  }
  // Once a device's cameras are known, settings it cannot honor are replaced:
  // a facing becomes that camera's id, an unlisted size or rate the closest.
  // `chosen`: the user picked the camera, so its settings fit at once.
  function fitWebcamToCamera(chosen) {
    if (!cameras || !cameras.length)
      return;
    if (webcamRunning && !chosen)
      return fitPending = true;
    var changes = cameraFitChanges(Webcam.chosenCamera(cameras, webcam.camera) || cameras[0]);
    if (Object.keys(changes).length)
      setWebcam(changes, true);
  }
  function cameraFitChanges(camera) {
    var changes = {};
    if (webcam.camera !== "id:" + camera.id)
      changes.camera = "id:" + camera.id;
    var preset = Webcam.webcamPresets().find(p => p.value === webcam.preset);
    if (webcam.size !== "auto" && camera.sizes.indexOf(webcam.size) < 0)
      changes.size = Webcam.pickCameraSize(camera, preset ? preset.size : webcam.size);
    if (Webcam.cameraFpsOptions(camera).every(o => o.value !== webcam.fps))
      changes.fps = Webcam.pickCameraFps(camera, webcam.fps);
    if (Webcam.cameraZoomOptions(camera).every(o => o.value !== webcam.zoom))
      changes.zoom = "1";
    return changes;
  }
  // Restarts the running webcam on its phone and output with these settings.
  function applyWebcam() {
    if (webcamChanged)
      session.restartWebcam(webcam);
  }
  // While another session runs, MirrorSession switches to the webcam.
  function launchWebcam() {
    if (!ready)
      return session.report("Select a device that is Ready before starting a webcam.", true, "webcam");
    session.launchWebcam(serial, webcam, webcamSink);
  }

  Command {
    id: cameraScan
    property string serial: ""
    onFinished: (code, output, error) => {
      var list = code === 0 ? Webcam.parseCameraList(output) : [];
      var errors = Object.assign({}, root.cameraScanErrors);
      errors[cameraScan.serial] = list.length ? "" : code === 0 ? "The phone listed no cameras. Camera capture needs Android 12+." : Model.commandError(code, output, error, "Camera list");
      root.cameraScanErrors = errors;
      var catalog = Object.assign({}, root.cameraCatalog);
      catalog[cameraScan.serial] = list;
      root.cameraCatalog = catalog;
      if (list.length && cameraScan.serial === root.serial)
        root.fitWebcamToCamera();
      // The page may have moved to another phone during the scan.
      Qt.callLater(root.scanCamerasIfNeeded);
    }
  }
  Command {
    id: webcamScan
    onFinished: (code, output, error) => {
      root.webcamOutputs = code === 0 ? output.trim().split("\n").filter(Boolean).map(line => {
        var fields = line.split("\t");
        return { value: fields[0], label: fields[0] + (fields[1] ? " · " + fields[1] : "") };
      }) : [];
      // The scan lists only loopback nodes, so the first one is a safe default.
      if (!root.webcamOutputs.some(row => row.value === root.webcamSink))
        root.webcamSink = root.webcamOutputs.length ? root.webcamOutputs[0].value : "";
      root.webcamScanError = code === 0 ? "" : error.trim();
      root.webcamIssue = root.webcamOutputs.length ? "" : code === 0 ? error.trim() : "scan-error";
    }
  }

  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    visible: !root.ready
    text: "Connect and authorize this device to use its camera."
    color: Util.alpha(Commons.Color.foreground, 0.7)
  }
  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    visible: cameraScan.busy || root.cameraScanError !== ""
    text: cameraScan.busy ? "Reading the phone's cameras…" : "⚠ " + root.cameraScanError
    color: cameraScan.busy ? Util.alpha(Commons.Color.foreground, 0.7) : Commons.Color.urgent
    wrapMode: Text.WordWrap
    font.pixelSize: Style.font.bodySmall
  }
  // Every cell has the same preferred width, so a long option label can
  // never widen the grid past the popup.
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.space(6)
    Dropdown {
      objectName: "omadroidWebcamCamera"
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.columnSpan: 2
      label: "Camera · Android 12+"
      value: root.webcam.camera
      // A saved camera id stays selectable before the list is read.
      options: Webcam.cameraOptions(root.cameras).concat(!root.cameras && /^id:/.test(root.webcam.camera) ? [{ value: root.webcam.camera, label: "Camera " + root.webcam.camera.slice(3) + " (saved)" }] : [])
      Accessible.name: "Phone camera"
      onChanged: value => {
        root.setWebcam({ camera: value }, true);
        root.fitWebcamToCamera(true);
      }
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Quality"
      value: root.webcam.preset
      options: Webcam.webcamPresets().map(p => ({ value: p.value, label: p.label })).concat([{ value: "custom", label: "Custom" }])
      Accessible.name: "Quality preset"
      onChanged: value => {
        if (value !== "custom")
          root.applyPreset(value);
      }
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Output"
      value: root.webcamSink
      options: root.webcamOutputs
      enabled: root.webcamOutputs.length > 0
      Accessible.name: "V4L2 loopback output"
      Controls.ToolTip.text: "The v4l2loopback device video apps read"
      Controls.ToolTip.visible: outputHover.hovered
      HoverHandler {
        id: outputHover
      }
      onChanged: value => root.webcamSink = value
    }
  }
  WebcamDetails {
    Layout.fillWidth: true
    options: root
  }
  RowLayout {
    Layout.fillWidth: true
    ActionButton {
      text: "Refresh"
      enabled: !webcamScan.busy && !cameraScan.busy
      tooltipText: "Find V4L2 outputs again and ask the phone for its cameras"
      onClicked: {
        root.refreshWebcamOutputs();
        root.refreshCameras();
      }
    }
  }
  WebcamSetupCard {
    id: setupCard
    Layout.fillWidth: true
    issue: root.webcamIssue
    scanError: root.webcamScanError
    outputsFound: root.webcamOutputs.length > 0
    panelOpen: root.panelOpen
    onRefreshRequested: root.refreshWebcamOutputs()
  }
}
