import QtQuick
import Quickshell.Io
import "Model.js" as Model

// The single scrcpy session (mirror, audio-only or webcam) of this machine.
// Non-visual. The session itself lives in session.sh's state file, so every
// instance (each monitor's panel, the global banner, a device page) sees the
// same session; one instance per panel is enough and is shared.
//
// Public API
//   Inputs:   missingTools, wakeOnLaunch, unlockOnLaunch
//   State:    sessionPid (0 = none), sessionSerial, sessionType
//             ("mirror" | "audio" | "webcam"), sessionAudioOnly,
//             sessionRecording, sessionSink (webcam output), sessionArgs
//             (running webcam command), busy (starting or running), stopping,
//             restartPending, terminalLaunched, message, failed,
//             runtimeDir, sessionScript, sessionTitle, stopLabel
//   Launch:   launchMirror(serial, profile, folder, audioOnly)
//             launchWebcam(serial, webcamSettings, sink)
//             restartWebcam(webcamSettings)  — Apply: same phone and output
//   Control:  stop(), toggleLog(), refreshSession(), report(text, isFailure)
//   Signal:   webcamArgsRead() — a running webcam's command was read back
//
// Usage:
//   MirrorSession {
//     id: mirrorSession
//     missingTools: root.missingTools
//     wakeOnLaunch: discovery.preferences.wakeOnLaunch
//   }
//   ActionButton { onClicked: mirrorSession.launchMirror("USB123", profile, "/home/me", false) }
//   Label { text: mirrorSession.busy ? mirrorSession.sessionTitle : "" }
Item {
  id: root
  visible: false
  // Supplied by the panel, which runs `session.sh check` on open.
  property string missingTools: ""
  // Plugin settings: wake or unlock the device before scrcpy starts.
  property bool wakeOnLaunch: true
  property bool unlockOnLaunch: false

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
  // The running webcam's command, to tell when the settings differ.
  property var sessionArgs: []
  property bool restartPending: false
  // The phone, output and settings an Apply restarts with: the running
  // session's phone and output, the settings shown when Apply was pressed.
  property var restartTarget: null
  // A webcam this instance launched may fail before any status saw it run;
  // its camera error is then still worth showing. Old errors are not, on
  // every later panel open.
  property bool webcamReportDue: false
  // True once a session ran, so its terminal (kept by --hold) has output.
  property bool terminalLaunched: false
  property bool statusPending: false
  property var pendingLaunch: []
  property string powerWarning: ""
  readonly property bool busy: sessionPid > 0 || launcher.busy || preparer.busy
  readonly property string runtimeDir: stateFile.path.replace(/\/session$/, "")
  readonly property string sessionScript: scriptPath("session.sh")
  readonly property string powerScript: scriptPath("device-power.sh")
  readonly property string kindLabel: sessionType === "webcam" ? "Webcam" : sessionAudioOnly ? "Audio only" : "Mirroring"
  // "Mirroring", "Starting"… for headers and the global banner.
  readonly property string sessionTitle: sessionPid > 0 ? kindLabel : "Starting"
  readonly property string stopLabel: stopping ? "Stopping…" : sessionType === "webcam" ? "Stop webcam" : sessionAudioOnly ? "Stop audio" : "Stop mirroring"

  signal webcamArgsRead

  Component.onCompleted: {
    statePath.start(["bash", sessionScript, "path"], 3);
    refreshSession();
  }

  function scriptPath(name) {
    return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""));
  }
  // Messages from the forms (profile saved, device not ready) share the
  // session's line, so one place reports what last happened.
  function report(text, isFailure) {
    failed = !!isFailure;
    message = String(text || "");
  }
  function toggleLog() {
    if (!logToggle.busy)
      logToggle.start(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"omadroid\")"], 3);
  }
  function missingToolsReason(starting) {
    return missingTools ? "Install " + missingTools + " before " + starting + "." : "";
  }
  // Example: launchMirror("USB123", Model.builtInProfiles()[0], "/home/me", false)
  function launchMirror(serial, profile, folder, audioOnly) {
    if (busy)
      return;
    var blocked = missingToolsReason("launching scrcpy");
    if (blocked)
      return report(blocked, true);
    try {
      var path = profile.record ? Model.recordingPath(folder, serial, new Date(), Math.random().toString(36).slice(2, 10), audioOnly ? "mka" : "mkv") : "";
      var args = audioOnly ? Model.audioOnlyCommand(serial, profile, path) : Model.scrcpyCommand(serial, profile, path);
      markStarting(serial, audioOnly ? "audio" : "mirror", path, "");
      report("Starting " + (audioOnly ? "audio" : "scrcpy") + " for " + serial + "…", false);
      startWithPower(serial, ["bash", sessionScript, "launch", serial, sessionType, path, "--"].concat(args));
    } catch (e) {
      report(e.message, true);
    }
  }
  // Example: launchWebcam("USB123", Model.webcamSettings(""), "/dev/video12")
  function launchWebcam(serial, settings, sink) {
    if (busy)
      return;
    var blocked = missingToolsReason("starting a webcam");
    if (!blocked && !sink)
      blocked = "No v4l2loopback output selected. Create one, then press Refresh.";
    if (blocked)
      return report(blocked, true);
    startWebcam(serial, settings, sink, false);
  }
  function startWebcam(serial, settings, sink, restarting) {
    try {
      var args = Model.webcamCommand(serial, settings, sink);
      sessionArgs = args;
      webcamReportDue = true;
      markStarting(serial, "webcam", "", sink);
      report((restarting ? "Restarting webcam for " : "Starting webcam for ") + serial + "…", false);
      // An Apply restart keeps the session's phone and output, and the apps
      // still reading that output (a call bridging the gap) do not block it.
      launcher.start((restarting ? ["env", "OMADROID_KEEP_READERS=1"] : []).concat(["bash", sessionScript, "launch", serial, "webcam", "", "--"]).concat(args), 10);
    } catch (e) {
      report(e.message, true);
    }
  }
  function markStarting(serial, type, recording, sink) {
    sessionSerial = serial;
    sessionType = type;
    sessionAudioOnly = type === "audio";
    sessionRecording = recording;
    sessionSink = sink;
    stopping = false;
  }
  // Stops the running webcam; the status handler starts it again once the
  // session has ended, with `settings`.
  function restartWebcam(settings) {
    if (sessionType !== "webcam" || sessionPid <= 0 || restartPending)
      return;
    restartTarget = { serial: sessionSerial, sink: sessionSink, settings: settings };
    restartPending = true;
    report("Restarting the webcam with the new settings…", false);
    stop();
  }
  function relaunchAfterRestart() {
    var target = restartTarget;
    restartTarget = null;
    if (target && !missingTools)
      startWebcam(target.serial, target.settings, target.sink, true);
  }

  // A failed wake or unlock is reported but never blocks the session: the
  // device can still be unlocked from the mirror window.
  function startWithPower(serial, launchArgs) {
    powerWarning = "";
    if (!wakeOnLaunch && !unlockOnLaunch)
      return launcher.start(launchArgs, 6);
    pendingLaunch = launchArgs;
    // Unlock: up to 8 s for the bouncer, 10 s typing, 4 s checking.
    preparer.start(["bash", powerScript, "connected", wakeOnLaunch ? "1" : "0", unlockOnLaunch ? "1" : "0", serial], 30);
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
  function applyActive(lines) {
    sessionSerial = lines[1];
    sessionType = lines[2] === "1" ? "audio" : lines[2] === "0" ? "mirror" : lines[2];
    sessionAudioOnly = sessionType === "audio";
    // A webcam's detail field holds its sink, not a recording.
    sessionRecording = sessionType === "webcam" ? "" : lines[3];
    sessionSink = sessionType === "webcam" ? lines[3] : "";
    sessionPid = Number(lines[4]) || 0;
    terminalLaunched = true;
    webcamReportDue = false;
    if (sessionType === "webcam" && sessionArgs.length === 0 && sessionPid > 0 && !argsReader.busy)
      argsReader.start(["xargs", "-0", "-a", "/proc/" + sessionPid + "/cmdline", "printf", "%s\n"], 3);
    if (!sessionWaiter.busy)
      sessionWaiter.start(["bash", sessionScript, "wait"], 0);
    // The card header already says the session is running.
    if (message.indexOf("Session started") === 0)
      message = "";
  }
  function applyEnded(lines, wasActive) {
    sessionPid = 0;
    sessionArgs = [];
    // The stopper's own message would land on the new launch; it
    // refreshes once more when it returns.
    if (restartPending) {
      if (!stopper.busy) {
        restartPending = false;
        Qt.callLater(relaunchAfterRestart);
      }
    } else if (lines[1] && sessionType === "webcam" && !stopping && (wasActive || webcamReportDue)) {
      webcamReportDue = false;
      report(lines[1], true);
    } else if (wasActive && !stopping && message.indexOf("Session stopped") !== 0 && message.indexOf("Session force-stopped") !== 0) {
      report(endedMessage(), false);
    } else if (message.indexOf("Session started") === 0) {
      message = "scrcpy exited. Press Show log for its output." + recordingNote();
    }
  }
  function recordingNote() {
    return sessionRecording ? " Recording: " + sessionRecording : "";
  }
  function endedMessage() {
    return (sessionType === "webcam" ? "Webcam session ended. Check Show log for camera or size errors." : sessionAudioOnly ? "Audio session ended." : "Mirroring ended.") + recordingNote();
  }

  // Nothing polls. Every instance watches the session file, which appears on
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
      if (code === 0 && lines[0] === "active" && lines.length >= 5)
        root.applyActive(lines);
      else if (code === 0)
        root.applyEnded(lines, wasActive);
      else
        root.report(Model.commandError(code, output, error, "Session status"), true);
      if (root.statusPending)
        Qt.callLater(root.refreshSession);
    }
  }
  // An instance created after the webcam started (shell reload, another
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
      root.webcamArgsRead();
    }
  }
  Command {
    id: logToggle
    onFinished: (code, output, error) => {
      if (code === 0 && output.trim() === "ok")
        return;
      root.report("Could not show the OmaDroid terminal: " + Model.commandError(code, output, error, "hyprctl"), true);
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
}
