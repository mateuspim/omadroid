import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtCore as Core
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

ColumnLayout {
  id: root
  required property var devices
  property string pageMode: "mirror"
  signal requestPage(string page)
  property string selectedSerial: ""
  property var profile: Model.builtInProfiles()[0]
  property string profileName: "Balanced"
  property string baseProfileName: "Balanced"
  property string message: ""
  property bool failed: false
  property bool stopping: false
  property string sessionSerial: ""
  property string sessionRecording: ""
  // The running webcam's output, from the session state, so every widget
  // previews what the session writes, whatever its own selection says.
  property string sessionSink: ""
  property bool sessionAudioOnly: false
  property string sessionType: "mirror"
  property int sessionPid: 0
  // Camera, quality and adjustments for the next webcam (Model.webcamSettings),
  // saved in omadroid.ini. Replaced whole by setWebcam() so bindings update.
  property var webcam: Model.webcamSettings("")
  // Each device's cameras (Model.parseCameraList), read once per serial.
  // A phone whose scan failed maps to [] (and its error), so it is not asked
  // again on every open; Refresh asks again.
  property var cameraCatalog: ({})
  property var cameraScanErrors: ({})
  readonly property string cameraScanError: cameraScanErrors[selectedSerial] || ""
  readonly property var cameras: cameraCatalog[selectedSerial] || null
  readonly property var currentCamera: Model.chosenCamera(cameras, webcam.camera)
  // The running webcam's command, to tell when the settings above differ.
  property var sessionArgs: []
  property bool restartPending: false
  // The phone and output an Apply restarts on: the running session's.
  property var restartTarget: null
  // A webcam this widget launched may fail before any status saw it run;
  // its camera error is then still worth showing. Old errors are not, on
  // every later panel open.
  property bool webcamReportDue: false
  // Set when the camera list arrives mid-session; fitting then would change
  // the shown settings and offer an Apply nobody asked for.
  property bool fitPending: false
  readonly property bool webcamRunning: sessionType === "webcam" && sessionPid > 0
  // While a webcam runs, Apply keeps its phone and output, whatever the
  // Device and output selections say.
  readonly property var nextWebcamArgs: {
    var serial = webcamRunning ? sessionSerial : selectedSerial;
    var sink = webcamRunning ? sessionSink : webcamSink;
    try {
      return (webcamRunning || selectedReady) && serial && sink ? Model.webcamCommand(serial, webcam, sink) : null;
    } catch (e) {
      return null;
    }
  }
  readonly property bool webcamChanged: webcamRunning && !stopping && sessionArgs.length > 0 && nextWebcamArgs !== null && JSON.stringify(nextWebcamArgs) !== JSON.stringify(sessionArgs)
  property string webcamSink: ""
  property var webcamOutputs: []
  property string webcamIssue: ""
  property string webcamScanError: ""
  property string setupMessage: ""
  property bool setupPending: false
  property double setupStartedAt: 0
  readonly property var webcamGuidance: Model.webcamSetup(webcamIssue)
  // Supplied by the panel, which runs `session.sh check` on open.
  property string missingTools: ""
  property bool panelOpen: true
  // Plugin settings: wake or unlock the device before scrcpy starts.
  property bool wakeOnLaunch: true
  property bool unlockOnLaunch: false
  property var pendingLaunch: []
  property string powerWarning: ""
  property bool optionsExpanded: false
  property bool webcamPreview: false
  property bool webcamDetailsOpen: false
  // A saved profile name awaiting a second Save, and a pending Remove.
  property string confirmOverwrite: ""
  property bool confirmRemove: false
  // True once a session ran, so its terminal (kept by --hold) has output.
  property bool terminalLaunched: false
  property bool statusPending: false
  readonly property bool busy: sessionPid > 0 || launcher.busy || preparer.busy
  // Where the folded options start, so the panel can scroll them into view.
  readonly property real optionsTop: nextOptionsToggle.y
  readonly property bool sessionMatchesPage: pageMode === "webcam" ? sessionType === "webcam" : sessionType !== "webcam"
  readonly property string sessionScript: decodeURIComponent(Qt.resolvedUrl("session.sh").toString().replace(/^file:\/\//, ""))
  readonly property string powerScript: decodeURIComponent(Qt.resolvedUrl("device-power.sh").toString().replace(/^file:\/\//, ""))
  readonly property string webcamScript: decodeURIComponent(Qt.resolvedUrl("webcam-devices.sh").toString().replace(/^file:\/\//, ""))
  readonly property string setupScript: decodeURIComponent(Qt.resolvedUrl("webcam-setup.sh").toString().replace(/^file:\/\//, ""))
  readonly property var readyDevices: devices.filter(row => row.status === "device")
  readonly property var customProfiles: Model.savedProfiles(saved.profilesJson)
  readonly property var profiles: Model.builtInProfiles().concat(customProfiles)
  readonly property var sessionDevice: devices.find(row => row.serial === sessionSerial) || null
  // The Android device name (or model) when discovery knows the device; the
  // serial (IP:port for wireless) otherwise, and always in the tooltip.
  readonly property string sessionName: sessionDevice ? sessionDevice.name : sessionSerial
  readonly property string sessionAddress: sessionDevice ? [sessionDevice.model !== sessionDevice.name ? sessionDevice.model : "", sessionDevice.transport, sessionSerial].filter(Boolean).join(" · ") : sessionSerial
  readonly property bool selectedReady: readyDevices.some(row => row.serial === selectedSerial)
  readonly property var deviceOptions: readyDevices.map(row => ({
        value: row.serial,
        label: row.name + " · " + row.transport + " · " + row.serial
      }))
  spacing: Style.space(6)

  Core.Settings {
    id: saved
    location: Util.fileUrl((Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/omadroid.ini")
    property string profilesJson: "[]"
    property string lastProfile: "Balanced"
    property string recordingFolder: Quickshell.env("HOME")
    property string webcamJson: ""
  }

  Component.onCompleted: {
    webcam = Model.webcamSettings(saved.webcamJson);
    selectProfile(saved.lastProfile);
    statePath.start(["bash", sessionScript, "path"], 3);
    refreshSession();
    refreshWebcamOutputs();
  }
  onPanelOpenChanged: if (panelOpen) {
    reloadWebcam();
    refreshSession();
    refreshWebcamOutputs();
    Qt.callLater(scanCamerasIfNeeded);
  }
  onPageModeChanged: Qt.callLater(scanCamerasIfNeeded)
  onSelectedReadyChanged: Qt.callLater(scanCamerasIfNeeded)
  onSelectedSerialChanged: {
    Qt.callLater(scanCamerasIfNeeded);
    if (cameras && cameras.length)
      fitWebcamToCamera();
  }
  // Each session starts with its options folded so the session controls fit.
  onBusyChanged: if (busy)
    optionsExpanded = false
  onReadyDevicesChanged: {
    // Preserve a vanished selection so unplugging cannot silently redirect a
    // launch to another phone. Only auto-select before any explicit choice.
    if (!selectedSerial && readyDevices.length)
      selectedSerial = readyDevices[0].serial;
  }

  function chooseDevice(serial) {
    selectedSerial = serial;
  }
  function selectProfile(name) {
    var found = profiles.find(p => p.name === name) || profiles[0];
    profile = Object.assign({}, found);
    profileName = found.name;
    baseProfileName = found.name;
    saved.lastProfile = found.name;
  }
  function changeOption(key, value) {
    var next = Object.assign({}, profile);
    next[key] = value;
    if (key === "screenOff" && value)
      next.keepActive = true;
    profile = next;
    profileName = "Custom";
  }
  function resetOptions() {
    selectProfile(baseProfileName);
    failed = false;
    message = "Options restored from “" + baseProfileName + "”.";
  }
  function saveProfile(name) {
    name = String(name || nameField.text).trim();
    var candidate = Object.assign({}, profile, {
      name: name
    });
    if (!Model.validProfile(candidate) || name === "Custom" || Model.builtInProfiles().some(p => p.name === name)) {
      failed = true;
      message = "Choose a name of 1–48 characters, different from Custom and the built-in profiles.";
      return;
    }
    if (customProfiles.some(p => p.name === name) && confirmOverwrite !== name) {
      confirmRemove = false;
      confirmOverwrite = name;
      failed = false;
      message = "“" + name + "” already exists. Press Replace to overwrite it.";
      confirmExpiry.restart();
      return;
    }
    confirmOverwrite = "";
    var list = customProfiles.filter(p => p.name !== name);
    if (list.length >= 30) {
      failed = true;
      message = "Remove a saved profile first (limit: 30).";
      return;
    }
    list.push(candidate);
    saved.profilesJson = JSON.stringify(list);
    selectProfile(name);
    nameField.text = "";
    failed = false;
    message = "Saved profile “" + name + "”.";
  }
  function removeProfile() {
    var name = profileName;
    if (!confirmRemove) {
      confirmOverwrite = "";
      confirmRemove = true;
      failed = false;
      message = "Press Confirm to remove “" + name + "”.";
      confirmExpiry.restart();
      return;
    }
    confirmRemove = false;
    saved.profilesJson = JSON.stringify(customProfiles.filter(p => p.name !== name));
    selectProfile("Balanced");
    failed = false;
    message = "Removed profile “" + name + "”.";
  }
  function cancelConfirmations() {
    if (confirmRemove || confirmOverwrite)
      message = "";
    confirmRemove = false;
    confirmOverwrite = "";
  }
  function toggleLog() {
    if (!logToggle.busy)
      logToggle.start(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"omadroid\")"], 3);
  }
  function launch(audioOnly) {
    if (busy)
      return;
    failed = false;
    if (missingTools) {
      failed = true;
      message = "Install " + missingTools + " before launching scrcpy.";
      return;
    }
    if (!selectedReady) {
      failed = true;
      message = "Select a device that is Ready before launching.";
      return;
    }
    try {
      var path = profile.record ? Model.recordingPath(folderField.text, selectedSerial, new Date(), Math.random().toString(36).slice(2, 10), audioOnly ? "mka" : "mkv") : "";
      var args = audioOnly ? Model.audioOnlyCommand(selectedSerial, profile, path) : Model.scrcpyCommand(selectedSerial, profile, path);
      sessionSerial = selectedSerial;
      sessionRecording = path;
      sessionAudioOnly = !!audioOnly;
      sessionType = audioOnly ? "audio" : "mirror";
      stopping = false;
      message = "Starting " + (audioOnly ? "audio" : "scrcpy") + " for " + selectedSerial + "…";
      startWithPower(["bash", sessionScript, "launch", selectedSerial, sessionType, path, "--"].concat(args));
    } catch (e) {
      failed = true;
      message = e.message;
    }
  }

  function refreshWebcamOutputs() {
    if (!webcamScan.busy)
      webcamScan.start(["bash", webcamScript, "list"], 3);
  }
  function openWebcamSetup() {
    if (webcamGuidance.step && !setupLauncher.busy)
      setupLauncher.start(["bash", setupScript, "open", webcamGuidance.step], 4);
  }
  function copyWebcamCommands() {
    if (webcamGuidance.commands && !setupClipboard.busy)
      setupClipboard.start(["wl-copy", "--type", "text/plain"], 4, webcamGuidance.commands);
  }
  // Only the widget showing the Webcam page asks, once per device.
  function scanCamerasIfNeeded() {
    if (pageMode === "webcam" && panelOpen && selectedReady && !cameraCatalog[selectedSerial])
      refreshCameras();
  }
  function refreshCameras() {
    if (!selectedReady || cameraScan.busy)
      return;
    cameraScan.serial = selectedSerial;
    cameraScan.start(["bash", webcamScript, "cameras", selectedSerial], 25);
  }
  // Every widget keeps its own copy; another monitor's widget may have
  // saved newer settings since.
  function reloadWebcam() {
    saved.sync();
    webcam = Model.webcamSettings(saved.value("webcamJson", saved.webcamJson));
  }
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
    var preset = Model.webcamPresets().find(p => p.value === name);
    if (preset)
      setWebcam({
        preset: name,
        size: Model.pickCameraSize(currentCamera, preset.size),
        fps: Model.pickCameraFps(currentCamera, preset.fps),
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
    if (webcamRunning && !chosen) {
      fitPending = true;
      return;
    }
    var changes = {};
    var camera = Model.chosenCamera(cameras, webcam.camera) || cameras[0];
    if (webcam.camera !== "id:" + camera.id)
      changes.camera = "id:" + camera.id;
    var preset = Model.webcamPresets().find(p => p.value === webcam.preset);
    if (webcam.size !== "auto" && camera.sizes.indexOf(webcam.size) < 0)
      changes.size = Model.pickCameraSize(camera, preset ? preset.size : webcam.size);
    if (Model.cameraFpsOptions(camera).every(o => o.value !== webcam.fps))
      changes.fps = Model.pickCameraFps(camera, webcam.fps);
    if (Model.cameraZoomOptions(camera).every(o => o.value !== webcam.zoom))
      changes.zoom = "1";
    if (Object.keys(changes).length)
      setWebcam(changes, true);
  }
  // Stops the running webcam; the status handler starts it again once the
  // session has ended, with the settings now shown.
  function applyWebcam() {
    if (!webcamChanged)
      return;
    restartTarget = { serial: sessionSerial, sink: sessionSink };
    restartPending = true;
    message = "Restarting the webcam with the new settings…";
    failed = false;
    stop();
  }
  function launchWebcam() {
    if (busy)
      return;
    failed = false;
    // An Apply restart keeps the session's phone and output, and the apps
    // still reading that output (a call bridging the gap) do not block it.
    var target = restartTarget;
    restartTarget = null;
    var serial = target ? target.serial : selectedSerial;
    var sink = target ? target.sink : webcamSink;
    var ready = readyDevices.some(row => row.serial === serial);
    if (missingTools || !ready || !sink) {
      failed = true;
      message = missingTools ? "Install " + missingTools + " before starting a webcam." :
        !ready ? "Select a device that is Ready before starting a webcam." : "No v4l2loopback output selected. Create one, then press Refresh.";
      return;
    }
    try {
      var args = Model.webcamCommand(serial, webcam, sink);
      sessionArgs = args;
      webcamReportDue = true;
      sessionSerial = serial;
      sessionRecording = "";
      sessionSink = sink;
      sessionType = "webcam";
      sessionAudioOnly = false;
      stopping = false;
      message = (target ? "Restarting webcam for " : "Starting webcam for ") + serial + "…";
      launcher.start((target ? ["env", "OMADROID_KEEP_READERS=1"] : []).concat(["bash", sessionScript, "launch", serial, "webcam", "", "--"]).concat(args), 10);
    } catch (e) {
      failed = true;
      message = e.message;
    }
  }

  Command {
    id: cameraScan
    property string serial: ""
    onFinished: (code, output, error) => {
      var list = code === 0 ? Model.parseCameraList(output) : [];
      var errors = Object.assign({}, root.cameraScanErrors);
      errors[cameraScan.serial] = list.length ? "" : code === 0 ? "The phone listed no cameras. Camera capture needs Android 12+." : Model.commandError(code, output, error, "Camera list");
      root.cameraScanErrors = errors;
      var catalog = Object.assign({}, root.cameraCatalog);
      catalog[cameraScan.serial] = list;
      root.cameraCatalog = catalog;
      if (list.length && cameraScan.serial === root.selectedSerial)
        root.fitWebcamToCamera();
      // The selection may have moved to another phone during the scan.
      Qt.callLater(root.scanCamerasIfNeeded);
    }
  }
  // A widget created after the webcam started (shell reload, another
  // monitor) reads its command from the running scrcpy for Apply.
  Command {
    id: argsReader
    onFinished: (code, output, error) => {
      if (code !== 0 || root.sessionType !== "webcam" || root.sessionPid <= 0)
        return;
      // From the first option on: a scrcpy wrapper script runs as
      // "bash /path/scrcpy …", while OmaDroid builds "scrcpy …".
      var list = output.split("\n").filter(Boolean);
      var first = list.findIndex(arg => arg.indexOf("--") === 0);
      root.sessionArgs = first < 0 ? [] : ["scrcpy"].concat(list.slice(first));
      // Another widget started it, possibly with settings saved since.
      root.reloadWebcam();
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
      if (root.webcamOutputs.length) {
        root.setupPending = false;
        root.setupMessage = "";
      }
    }
  }
  Command {
    id: setupLauncher
    onFinished: (code, output, error) => {
      if (code === 0) {
        root.setupPending = true;
        root.setupStartedAt = Date.now();
      }
      root.setupMessage = code === 0 ? "Finish setup in the terminal. Outputs will refresh here automatically." :
        Model.commandError(code, output, error, "webcam setup");
    }
  }
  Timer {
    interval: 3000
    repeat: true
    running: root.setupPending && root.panelOpen && root.webcamOutputs.length === 0
    onTriggered: {
      if (Date.now() - root.setupStartedAt > 300000)
        root.setupPending = false;
      else
        root.refreshWebcamOutputs();
    }
  }
  Command {
    id: setupClipboard
    onFinished: (code, output, error) => {
      root.setupMessage = code === 0 ? "Commands copied. Paste them into a terminal." :
        Model.commandError(code, output, error, "copy setup commands");
    }
  }

  // A failed wake or unlock is reported but never blocks the session: the
  // device can still be unlocked from the mirror window.
  function startWithPower(launchArgs) {
    powerWarning = "";
    if (!wakeOnLaunch && !unlockOnLaunch)
      return launcher.start(launchArgs, 6);
    pendingLaunch = launchArgs;
    // Unlock: up to 8 s for the bouncer, 10 s typing, 4 s checking.
    preparer.start(["bash", powerScript, "connected", wakeOnLaunch ? "1" : "0", unlockOnLaunch ? "1" : "0", selectedSerial], 30);
  }

  function stop() {
    if (!busy || stopping)
      return;
    stopping = true;
    // Up to 4 s for a clean exit plus 2 s after SIGKILL.
    stopper.start(["bash", sessionScript, "stop"], 10);
  }

  // A change arriving mid-read is re-read once that read finishes.
  function refreshSession() {
    if (status.busy)
      return statusPending = true;
    statusPending = false;
    status.start(["bash", sessionScript, "status"], 3);
  }
  // Nothing polls. Every widget watches the session file, which appears on
  // launch and disappears when a session ends, and while a session runs one
  // `session.sh wait` sleeps until scrcpy exits, then ends the session and
  // releases its owned rotation lock, even with the popup closed.
  Command {
    id: statePath
    onFinished: (code, output, error) => {
      if (code === 0)
        stateFile.path = output.trim();
    }
  }
  FileView {
    id: stateFile
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshSession()
  }
  Command {
    id: sessionWaiter
    onFinished: (code, output, error) => root.refreshSession()
  }
  Command {
    id: status
    onFinished: (code, output, error) => {
      var lines = output.trim().split("\n");
      var wasActive = root.sessionPid > 0;
      if (code === 0 && lines[0] === "active" && lines.length >= 5) {
        root.sessionSerial = lines[1];
        root.sessionType = lines[2] === "1" ? "audio" : lines[2] === "0" ? "mirror" : lines[2];
        root.sessionAudioOnly = root.sessionType === "audio";
        // A webcam's detail field holds its sink, not a recording.
        root.sessionRecording = root.sessionType === "webcam" ? "" : lines[3];
        root.sessionSink = root.sessionType === "webcam" ? lines[3] : "";
        root.sessionPid = Number(lines[4]) || 0;
        root.terminalLaunched = true;
        root.webcamReportDue = false;
        if (root.sessionType === "webcam" && root.sessionArgs.length === 0 && root.sessionPid > 0 && !argsReader.busy)
          argsReader.start(["xargs", "-0", "-a", "/proc/" + root.sessionPid + "/cmdline", "printf", "%s\n"], 3);
        if (!sessionWaiter.busy)
          sessionWaiter.start(["bash", root.sessionScript, "wait"], 0);
        // The card header already says the session is running.
        if (root.message.indexOf("Session started") === 0)
          root.message = "";
      } else if (code === 0) {
        root.sessionPid = 0;
        root.sessionArgs = [];
        if (root.fitPending) {
          root.fitPending = false;
          Qt.callLater(root.fitWebcamToCamera);
        }
        // The stopper's own message would land on the new launch; it
        // refreshes once more when it returns.
        if (root.restartPending) {
          if (!stopper.busy) {
            root.restartPending = false;
            Qt.callLater(root.launchWebcam);
          }
        } else if (lines[1] && root.sessionType === "webcam" && !root.stopping && (wasActive || root.webcamReportDue)) {
          root.webcamReportDue = false;
          root.failed = true;
          root.message = lines[1];
        } else if (wasActive && !root.stopping && root.message.indexOf("Session stopped") !== 0 && root.message.indexOf("Session force-stopped") !== 0) {
          root.failed = false;
          root.message = (root.sessionType === "webcam" ? "Webcam session ended. Check Show log for camera or size errors." : root.sessionAudioOnly ? "Audio session ended." : "Mirroring ended.") + (root.sessionRecording ? " Recording: " + root.sessionRecording : "");
        } else if (root.message.indexOf("Session started") === 0) {
          root.message = "scrcpy exited. Press Show log for its output." + (root.sessionRecording ? " Recording: " + root.sessionRecording : "");
        }
      } else {
        root.failed = true;
        root.message = Model.commandError(code, output, error, "Session status");
      }
      if (root.statusPending)
        Qt.callLater(root.refreshSession);
    }
  }
  Timer {
    id: confirmExpiry
    interval: 5000
    onTriggered: root.cancelConfirmations()
  }
  onProfileNameChanged: if (confirmRemove)
    cancelConfirmations()
  Command {
    id: logToggle
    onFinished: (code, output, error) => {
      if (code === 0 && output.trim() === "ok")
        return;
      root.failed = true;
      root.message = "Could not show the OmaDroid terminal: " + Model.commandError(code, output, error, "hyprctl");
    }
  }
  Command {
    id: launcher
    onFinished: (code, output, error) => {
      root.failed = code !== 0;
      if (code === 0)
        root.terminalLaunched = true;
      // The session file can report the session active before the launcher
      // returns; the card header then already says so.
      root.message = root.failed ? Model.commandError(code, output, error, "scrcpy launch") : root.powerWarning || (root.sessionPid > 0 ? "" : output.trim());
      root.refreshSession();
    }
  }
  Command {
    id: preparer
    onFinished: (code, output, error) => {
      if (code !== 0)
        root.powerWarning = "Device power: " + Model.commandError(code, output, error, "Wake/unlock");
      launcher.start(root.pendingLaunch, 6);
      root.pendingLaunch = [];
    }
  }
  Command {
    id: stopper
    onFinished: (code, output, error) => {
      root.failed = code !== 0;
      if (root.failed)
        root.restartPending = false;
      if (!root.restartPending)
        root.message = root.failed ? Model.commandError(code, output, error, "scrcpy stop") : output.trim();
      root.stopping = false;
      root.refreshSession();
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Label {
      Layout.fillWidth: true
      text: root.pageMode === "webcam" ? "Android webcam" : "Mirror with scrcpy"
      font.bold: true
      font.pixelSize: Style.font.title
    }
    Label {
      visible: root.busy
      text: root.stopping ? "Stopping…" : root.sessionPid === 0 ? "Starting…" : root.sessionType === "webcam" ? "● Webcam active" : root.sessionAudioOnly ? "● Audio active" : "● Mirroring active"
      color: Color.accent
      Accessible.name: text
    }
  }
  Rectangle {
    objectName: "omadroidOtherSession"
    Layout.fillWidth: true
    visible: root.busy && !root.sessionMatchesPage
    implicitHeight: otherSessionContent.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.06)
    border.color: Util.alpha(Color.accent, 0.4)
    ColumnLayout {
      id: otherSessionContent
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(12) }
      spacing: Style.space(6)
      Label {
        Layout.fillWidth: true
        text: (root.sessionPid === 0 ? "Starting " : "") + (root.sessionType === "webcam" ? "webcam" : root.sessionAudioOnly ? "audio" : "mirroring") + " · " + root.sessionName
        font.bold: true
        elide: Text.ElideRight
      }
      Label {
        Layout.fillWidth: true
        text: "End this session before starting " + (root.pageMode === "webcam" ? "the webcam." : "mirroring.")
        wrapMode: Text.WordWrap
        color: Util.alpha(Color.foreground, 0.7)
      }
      RowLayout {
        Layout.fillWidth: true
        ActionButton {
          text: root.sessionType === "webcam" ? "Webcam controls" : "Mirror controls"
          onClicked: root.requestPage(root.sessionType === "webcam" ? "webcam" : "mirror")
        }
        ActionButton {
          text: root.stopping ? "Stopping…" : root.sessionType === "webcam" ? "Stop webcam" : root.sessionAudioOnly ? "Stop audio" : "Stop mirroring"
          enabled: root.sessionPid > 0 && !root.stopping
          onClicked: root.stop()
        }
      }
    }
  }
  // While a session runs, its controls come first; the options below only
  // affect the next launch, so they fold away until asked for.
  Rectangle {
    objectName: "omadroidSessionCard"
    Layout.fillWidth: true
    visible: root.busy && root.sessionMatchesPage
    implicitHeight: sessionCardContent.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.06)
    border.color: Util.alpha(Color.accent, 0.4)
    ColumnLayout {
      id: sessionCardContent
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(12)
      }
      spacing: Style.space(6)
      RowLayout {
        Layout.fillWidth: true
        Label {
          Layout.fillWidth: true
          // A wrapped label reports its unwrapped width; with three buttons
          // beside it, that could widen the popup.
          Layout.preferredWidth: 1
          text: (root.sessionPid > 0 ? (root.sessionType === "webcam" ? "Webcam" : root.sessionAudioOnly ? "Audio only" : "Mirroring") : "Starting") + (root.sessionName ? " · " + root.sessionName : "")
          font.bold: true
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 2
          elide: Text.ElideRight
          Accessible.name: text + (root.sessionAddress !== root.sessionName ? ", " + root.sessionAddress : "")
          Controls.ToolTip.text: root.sessionAddress
          Controls.ToolTip.visible: sessionNameHover.hovered && root.sessionAddress !== ""
          HoverHandler {
            id: sessionNameHover
          }
        }
        ActionButton {
          text: root.webcamPreview ? "Hide preview" : "Preview"
          visible: root.sessionType === "webcam"
          enabled: root.sessionPid > 0 && root.sessionSink !== ""
          tooltipText: "Show what video apps receive from " + root.sessionSink
          onClicked: root.webcamPreview = !root.webcamPreview
        }
        ActionButton {
          text: "Show log"
          tooltipText: "Show or hide the hidden terminal running scrcpy"
          onClicked: root.toggleLog()
        }
        ActionButton {
          text: root.stopping ? "Stopping…" : root.sessionType === "webcam" ? "Stop webcam" : root.sessionAudioOnly ? "Stop audio" : "Stop mirroring"
          selected: true
          enabled: root.sessionPid > 0 && !root.stopping
          tooltipText: "Request a clean scrcpy shutdown so recordings can finalize"
          onClicked: root.stop()
        }
      }
      Label {
        Layout.fillWidth: true
        readonly property var battery: root.sessionDevice && root.sessionDevice.info ? root.sessionDevice.info.battery : null
        visible: text !== ""
        text: battery ? "Battery " + Model.batteryLabel(battery) : ""
        color: Util.alpha(Color.foreground, 0.7)
      }
      Label {
        Layout.fillWidth: true
        visible: root.sessionRecording !== ""
        text: "Recording: " + root.sessionRecording
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        color: Util.alpha(Color.foreground, 0.7)
        font.pixelSize: Style.font.bodySmall
        Accessible.name: text
      }
      Label {
        Layout.fillWidth: true
        visible: root.message !== ""
        text: (root.failed ? "⚠ " : "") + root.message
        color: root.failed ? Color.urgent : Color.accent
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 3
        elide: Text.ElideRight
        font.pixelSize: Style.font.bodySmall
        Accessible.name: text
      }
      RowLayout {
        objectName: "omadroidWebcamApply"
        Layout.fillWidth: true
        visible: root.webcamChanged
        Label {
          Layout.fillWidth: true
          // A wrapped label still reports its unwrapped width as implicit.
          Layout.preferredWidth: 1
          text: "Webcam settings changed since this session started."
          wrapMode: Text.WordWrap
          color: Util.alpha(Color.foreground, 0.7)
          font.pixelSize: Style.font.bodySmall
        }
        ActionButton {
          text: "Apply · restart"
          selected: true
          enabled: !root.restartPending
          tooltipText: "Restart the webcam with the new settings; video apps see a short gap"
          onClicked: root.applyWebcam()
        }
      }
      // Only while visible: an open preview keeps reading and decoding frames.
      Loader {
        id: previewLoader
        objectName: "omadroidWebcamPreview"
        Layout.fillWidth: true
        active: root.webcamPreview && root.sessionType === "webcam" && root.pageMode === "webcam" && root.sessionPid > 0 && !root.stopping && root.panelOpen && root.sessionSink !== ""
        // Named: the session-status Command is also called `status`.
        visible: active && previewLoader.status === Loader.Ready
        source: "WebcamPreview.qml"
        onLoaded: {
          item.device = Qt.binding(() => root.sessionSink);
          item.runtimeDir = Qt.binding(() => stateFile.path.replace(/\/session$/, ""));
          // Small while the options below are open, so both fit the popup.
          item.maxHeight = Qt.binding(() => root.optionsExpanded ? 160 : 320);
        }
      }
      Label {
        Layout.fillWidth: true
        visible: previewLoader.active && previewLoader.status === Loader.Error
        text: "The preview could not load. Check the shell log for WebcamPreview.qml."
        color: Color.urgent
        wrapMode: Text.WordWrap
      }
      ScreenPowerControls {
        Layout.fillWidth: true
        visible: root.sessionType === "mirror" && root.sessionMatchesPage
        sessionActive: root.busy && !root.stopping && root.sessionType === "mirror" && root.sessionMatchesPage
        sessionPid: root.sessionPid
      }
      ScreenRotationControls {
        Layout.fillWidth: true
        visible: root.sessionType === "mirror" && root.sessionMatchesPage
        sessionActive: root.busy && !root.stopping && root.sessionType === "mirror" && root.sessionMatchesPage
        sessionPid: root.sessionPid
        deviceSerial: root.sessionSerial
        sessionScript: root.sessionScript
      }
    }
  }
  ActionButton {
    id: nextOptionsToggle
    Layout.fillWidth: true
    visible: root.busy && root.sessionMatchesPage
    text: (root.optionsExpanded ? "▾ " : "▸ ") + "Next session options"
    tooltipText: "Options apply to the next launch, not the running session"
    Accessible.role: Accessible.Button
    Accessible.checkable: true
    Accessible.checked: root.optionsExpanded
    Accessible.name: "Next session options"
    onClicked: root.optionsExpanded = !root.optionsExpanded
  }
  ColumnLayout {
    objectName: "omadroidNextOptions"
    Layout.fillWidth: true
    visible: !root.busy || root.optionsExpanded || !root.sessionMatchesPage
    spacing: root.spacing
    Label {
      Layout.fillWidth: true
      visible: readyDevices.length === 0 || (!!selectedSerial && !selectedReady)
      text: readyDevices.length === 0 ? "Connect and authorize a device to start " + (root.pageMode === "webcam" ? "a webcam." : "mirroring.") : "The selected device is no longer ready. Choose another device or reconnect it."
      color: Util.alpha(Color.foreground, 0.7)
    }
    GridLayout {
      Layout.fillWidth: true
      columns: root.pageMode === "webcam" ? 1 : 2
      columnSpacing: Style.space(8)
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Device"
        value: root.selectedSerial
        options: root.deviceOptions
        enabled: (!root.busy || !root.sessionMatchesPage) && root.readyDevices.length > 0
        Accessible.name: root.pageMode === "webcam" ? "Webcam device" : "Mirror device"
        onChanged: value => root.chooseDevice(value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        visible: root.pageMode === "mirror"
        label: "Profile"
        value: root.profileName
        options: root.profiles.map(p => p.name).concat(root.profileName === "Custom" ? ["Custom"] : [])
        Accessible.name: "Launch profile"
        onChanged: value => {
          if (value !== "Custom")
            root.selectProfile(value);
        }
      }
    }
    GridLayout {
      objectName: "omadroidMirrorResolution"
      Layout.fillWidth: true
      visible: root.pageMode === "mirror"
      columns: 2
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(4)
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Resolution"
        value: root.profile.maxSize
        options: [
          {
            value: "0",
            label: "Native"
          },
          { value: "720", label: "720 px edge" },
          { value: "1080", label: "1080 px edge" },
          { value: "1440", label: "1440 px edge" },
          { value: "1920", label: "1080p · 1920 edge" },
          { value: "2560", label: "1440p · 2560 edge" },
          { value: "3840", label: "4K · 3840 edge" }]
        Accessible.name: "Resolution maximum edge"
        onChanged: value => root.changeOption("maxSize", value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "FPS limit"
        value: root.profile.fps
        options: [
          {
            value: "0",
            label: "Unlimited"
          },
          "15", "24", "30", "60", "90", "120"]
        Accessible.name: "FPS limit"
        onChanged: value => root.changeOption("fps", value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Codec"
        value: root.profile.codec
        options: [
          {
            value: "h264",
            label: "H.264"
          },
          {
            value: "h265",
            label: "H.265"
          },
          {
            value: "av1",
            label: "AV1"
          }
        ]
        Accessible.name: "Video codec"
        onChanged: value => root.changeOption("codec", value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Bitrate"
        value: root.profile.bitrate
        options: ["2", "4", "8", "12", "16", "20", "32", "50", "60"]
        Accessible.name: "Video bitrate in megabits per second"
        onChanged: value => root.changeOption("bitrate", value)
      }
    }
    GridLayout {
      Layout.fillWidth: true
      visible: root.pageMode === "mirror"
      columns: 2
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(4)
      Repeater {
        model: [
          {
            key: "audio",
            label: "Audio",
            tip: "Forward Android audio; support depends on the Android version"
          },
          {
            key: "record",
            label: "Recording",
            tip: "Record video as MKV or an audio-only session as MKA"
          },
          {
            key: "screenOff",
            label: "Device screen off",
            tip: "Turn the phone display off when the next video session starts"
          },
          {
            key: "keepActive",
            label: "Prevent idle sleep",
            tip: "Prevent Android inactivity sleep during the next video session"
          },
          {
            key: "fullscreen",
            label: "Fullscreen",
            tip: "Start the next scrcpy video window in fullscreen"
          }
        ]
        delegate: ActionButton {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          readonly property bool optionSelected: modelData.key === "keepActive" ? Model.preventsIdleSleep(root.profile) : root.profile[modelData.key]
          text: (optionSelected ? "✓ " : "○ ") + modelData.label
          selected: optionSelected
          tooltipText: modelData.tip
          Accessible.role: Accessible.CheckBox
          Accessible.checkable: true
          Accessible.checked: optionSelected
          Accessible.name: modelData.label
          onClicked: root.changeOption(modelData.key, !optionSelected)
        }
      }
    }
    TextField {
      id: folderField
      Layout.fillWidth: true
      visible: root.pageMode === "mirror" && root.profile.record
      text: saved.recordingFolder
      placeholderText: "Existing recording folder · absolute path"
      Accessible.name: "Recording folder"
      Controls.ToolTip.text: "A unique MKV is created for video; audio-only creates MKA. Stop the session to finalize it."
      Controls.ToolTip.visible: hovered
      onEditingFinished: saved.recordingFolder = text.trim()
    }
    RowLayout {
      Layout.fillWidth: true
      visible: root.pageMode === "mirror"
      TextField {
        id: nameField
        Layout.fillWidth: true
        maximumLength: 48
        placeholderText: "Save options as…"
        Accessible.name: "Profile name"
        onAccepted: root.saveProfile()
        onTextChanged: if (root.confirmOverwrite && text.trim() !== root.confirmOverwrite)
          root.cancelConfirmations()
      }
      ActionButton {
        readonly property bool replacing: root.confirmOverwrite !== "" && root.confirmOverwrite === nameField.text.trim()
        text: replacing ? "Replace" : "Save"
        selected: replacing
        enabled: nameField.text.trim() !== ""
        tooltipText: replacing ? "Overwrite the saved profile with the current options" : "Save the current options as a reusable profile"
        onClicked: root.saveProfile()
      }
      ActionButton {
        text: root.confirmRemove ? "Confirm" : "Remove"
        selected: root.confirmRemove
        visible: root.customProfiles.some(p => p.name === root.profileName)
        tooltipText: root.confirmRemove ? "Remove “" + root.profileName + "” permanently" : "Remove this saved profile"
        onClicked: root.removeProfile()
      }
      ActionButton {
        text: "Reset"
        enabled: root.profileName === "Custom"
        tooltipText: "Restore options from “" + root.baseProfileName + "” without changing saved profiles or connections"
        onClicked: root.resetOptions()
      }
    }
  }
  ColumnLayout {
    objectName: "omadroidWebcamOptions"
    Layout.fillWidth: true
    visible: root.pageMode === "webcam" && (!root.busy || root.optionsExpanded || !root.sessionMatchesPage)
    spacing: root.spacing
    Label {
      text: "Camera settings · Android 12+"
      font.bold: true
      font.pixelSize: Style.font.title
    }
    Label {
      Layout.fillWidth: true
      visible: cameraScan.busy || root.cameraScanError !== ""
      text: cameraScan.busy ? "Reading the phone's cameras…" : "⚠ " + root.cameraScanError
      color: cameraScan.busy ? Util.alpha(Color.foreground, 0.7) : Color.urgent
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
        label: "Camera"
        value: root.webcam.camera
        // A saved camera id stays selectable before the list is read.
        options: Model.cameraOptions(root.cameras).concat(!root.cameras && /^id:/.test(root.webcam.camera) ? [{ value: root.webcam.camera, label: "Camera " + root.webcam.camera.slice(3) + " (saved)" }] : [])
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
        options: Model.webcamPresets().map(p => ({ value: p.value, label: p.label })).concat([{ value: "custom", label: "Custom" }])
        Accessible.name: "Quality preset"
        onChanged: value => {
          if (value !== "custom")
            root.applyPreset(value);
        }
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "V4L2 output"
        value: root.webcamSink
        options: root.webcamOutputs
        enabled: root.webcamOutputs.length > 0
        Accessible.name: "V4L2 loopback output"
        onChanged: value => root.webcamSink = value
      }
    }
    // Folded by default, with what is set beside it. Buttons never elide,
    // so the summary is a label that does; a long button widened the popup.
    RowLayout {
      objectName: "omadroidWebcamDetailsToggle"
      Layout.fillWidth: true
      ActionButton {
        text: (root.webcamDetailsOpen ? "▾ " : "▸ ") + "Quality and adjustments"
        tooltipText: "Resolution, frame rate, bitrate, codec, orientation, zoom, smoothing and torch"
        Accessible.role: Accessible.Button
        Accessible.checkable: true
        Accessible.checked: root.webcamDetailsOpen
        onClicked: root.webcamDetailsOpen = !root.webcamDetailsOpen
      }
      Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        text: Model.webcamSummary(root.webcam)
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        color: Util.alpha(Color.foreground, 0.6)
        font.pixelSize: Style.font.bodySmall
        Accessible.name: "Current settings: " + text
      }
    }
    GridLayout {
      objectName: "omadroidWebcamDetails"
      Layout.fillWidth: true
      visible: root.webcamDetailsOpen
      columns: 2
      columnSpacing: Style.space(6)
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Resolution"
        value: root.webcam.size
        options: Model.cameraSizeOptions(root.currentCamera)
        Accessible.name: "Camera capture size"
        onChanged: value => root.setWebcam({ size: value })
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Frame rate"
        value: root.webcam.fps
        options: Model.cameraFpsOptions(root.currentCamera)
        Accessible.name: "Camera frame rate"
        onChanged: value => root.setWebcam({ fps: value })
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Bitrate"
        value: root.webcam.bitRate
        options: ["4", "6", "8", "12", "16", "24", "32", "40"].map(n => ({ value: n, label: n + " Mbps" }))
        Accessible.name: "Video bitrate"
        onChanged: value => root.setWebcam({ bitRate: value })
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Codec"
        value: root.webcam.codec
        options: [{ value: "h265", label: "H.265 · sharper" }, { value: "h264", label: "H.264 · compatible" }]
        Accessible.name: "Video codec"
        onChanged: value => root.setWebcam({ codec: value })
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Orientation"
        value: root.webcam.orientation
        options: [{ value: "0", label: "Normal" }, { value: "90", label: "Rotate 90°" }, { value: "180", label: "Rotate 180°" }, { value: "270", label: "Rotate 270°" }, { value: "flip0", label: "Mirror" }, { value: "flip90", label: "Mirror · 90°" }, { value: "flip180", label: "Mirror · 180°" }, { value: "flip270", label: "Mirror · 270°" }]
        Accessible.name: "Camera orientation"
        onChanged: value => root.setWebcam({ orientation: value }, true)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Zoom"
        value: root.webcam.zoom
        options: Model.cameraZoomOptions(root.currentCamera)
        Accessible.name: "Camera zoom"
        onChanged: value => root.setWebcam({ zoom: value }, true)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Smoothing"
        value: root.webcam.buffer
        options: [{ value: "0", label: "Off" }, { value: "50", label: "50 ms" }, { value: "100", label: "100 ms" }, { value: "200", label: "200 ms" }]
        Accessible.name: "Wi-Fi smoothing buffer"
        Controls.ToolTip.text: "Delay frames a little to hide Wi-Fi stutter"
        Controls.ToolTip.visible: smoothingHover.hovered
        HoverHandler {
          id: smoothingHover
        }
        onChanged: value => root.setWebcam({ buffer: value }, true)
      }
      ActionButton {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignBottom
        text: (root.webcam.torch ? "✓ " : "○ ") + "Torch"
        selected: root.webcam.torch
        tooltipText: "Turn on the camera light while the webcam runs, on cameras that have one"
        Accessible.role: Accessible.Button
        Accessible.checkable: true
        Accessible.checked: root.webcam.torch
        onClicked: root.setWebcam({ torch: !root.webcam.torch }, true)
      }
    }
    RowLayout {
      Layout.fillWidth: true
      ActionButton {
        objectName: "omadroidWebcamStart"
        readonly property bool applies: root.sessionType === "webcam" && root.busy
        text: applies ? "Apply · restart" : "Start webcam"
        selected: true
        enabled: applies ? root.webcamChanged && !root.restartPending : root.selectedReady && root.webcamSink !== "" && !root.missingTools && !root.busy
        tooltipText: applies ? "Restart the running webcam with these settings" : "Start the phone camera as a webcam"
        onClicked: applies ? root.applyWebcam() : root.launchWebcam()
      }
      ActionButton {
        text: "Refresh"
        enabled: !webcamScan.busy && !cameraScan.busy
        tooltipText: "Find V4L2 outputs again and ask the phone for its cameras"
        onClicked: {
          root.refreshWebcamOutputs();
          root.refreshCameras();
        }
      }
      Item {
        Layout.fillWidth: true
      }
      ActionButton {
        text: "Show log"
        visible: root.terminalLaunched
        onClicked: root.toggleLog()
      }
    }
    Rectangle {
      objectName: "omadroidWebcamSetup"
      Layout.fillWidth: true
      visible: root.webcamOutputs.length === 0
      implicitHeight: setupContent.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Util.alpha(Color.urgent, 0.06)
      border.color: Util.alpha(Color.urgent, 0.4)
      ColumnLayout {
        id: setupContent
        anchors {
          left: parent.left
          right: parent.right
          top: parent.top
          margins: Style.space(12)
        }
        spacing: Style.space(6)
        Label {
          Layout.fillWidth: true
          text: root.webcamGuidance.title
          color: Color.urgent
          font.bold: true
          Accessible.name: text
        }
        Label {
          Layout.fillWidth: true
          text: root.webcamGuidance.detail + (root.webcamScanError ? " " + root.webcamScanError : "")
          wrapMode: Text.WordWrap
        }
        RowLayout {
          Layout.fillWidth: true
          ActionButton {
            text: root.webcamGuidance.action
            selected: true
            visible: root.webcamGuidance.step !== ""
            enabled: !setupLauncher.busy
            tooltipText: "Open a visible terminal. Installation or module loading starts only when you click."
            onClicked: root.openWebcamSetup()
          }
          ActionButton {
            text: "Copy commands"
            visible: root.webcamGuidance.commands !== ""
            enabled: !setupClipboard.busy
            tooltipText: "Copy manual setup commands to the clipboard"
            onClicked: root.copyWebcamCommands()
          }
        }
        Label {
          Layout.fillWidth: true
          visible: root.setupMessage !== ""
          text: root.setupMessage
          wrapMode: Text.WordWrap
          color: Util.alpha(Color.foreground, 0.8)
        }
      }
    }
  }
  RowLayout {
    objectName: "omadroidMirrorLaunch"
    Layout.fillWidth: true
    visible: root.pageMode === "mirror" && !root.busy
    ActionButton {
      text: "Launch scrcpy"
      selected: true
      enabled: root.selectedReady && !root.missingTools
      tooltipText: "Start video mirroring with the selected options"
      onClicked: root.launch(false)
    }
    ActionButton {
      text: "Audio only"
      enabled: root.selectedReady && !root.missingTools
      tooltipText: "Start windowless audio; stop it here in OmaDroid"
      onClicked: root.launch(true)
    }
    Item {
      Layout.fillWidth: true
    }
    ActionButton {
      text: "Show log"
      visible: root.terminalLaunched
      tooltipText: "Show or hide the terminal of the last session, with scrcpy's output"
      onClicked: root.toggleLog()
    }
  }
  Label {
    Layout.fillWidth: true
    visible: root.message !== "" && !root.busy
    text: (root.failed ? "⚠ " : "") + root.message
    color: root.failed ? Color.urgent : Color.accent
    wrapMode: Text.WrapAnywhere
    maximumLineCount: 3
    elide: Text.ElideRight
    Accessible.name: text
  }
}
