import QtQuick
import Quickshell.Io
import "Model.js" as Model
import "Webcam.js" as Webcam

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
//             pendingSwitch, restartPending, previewWanted,
//             terminalLaunched, message, failed,
//             runtimeDir, sessionScript, sessionTitle, stopLabel
//   Launch:   launchMirror(serial, profile, folder, audioOnly) — while a
//             session runs, any launch switches to it (switchTo)
//             launchWebcam(serial, webcamSettings, sink)
//             restartWebcam(webcamSettings)  — Apply: same phone and output
//   Control:  stop(), toggleLog(), refreshSession(), report(text, isFailure, kind?)
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
  // The section the message belongs to ("mirror" | "webcam" | "" = both), so
  // a webcam error doesn't also show under Mirror.
  property string messageKind: ""
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
  // A launch waiting for the running session to stop: {kind, serial, launch}.
  // Starting anything while a session runs switches to it (one session at a
  // time); Apply is a switch to the same webcam with new settings.
  property var pendingSwitch: null
  readonly property bool restartPending: pendingSwitch !== null
  // Set when this instance starts a webcam, so its section opens the preview.
  property bool previewWanted: false
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
  readonly property string sessionScript: scriptPath("scripts/session.sh")
  readonly property string powerScript: scriptPath("scripts/device-power.sh")
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
  function report(text, isFailure, kind) {
    if (kind !== undefined)
      messageKind = kind;
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
      return switchTo(audioOnly ? "audio" : "mirror", serial, () => launchMirror(serial, profile, folder, audioOnly));
    messageKind = "mirror";
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
  // Example: launchWebcam("USB123", Webcam.webcamSettings(""), "/dev/video12")
  function launchWebcam(serial, settings, sink) {
    if (busy)
      return switchTo("webcam", serial, () => launchWebcam(serial, settings, sink));
    messageKind = "webcam";
    var blocked = missingToolsReason("starting a webcam");
    if (!blocked && !sink)
      blocked = "No v4l2loopback output selected. Create one, then press Refresh.";
    if (blocked)
      return report(blocked, true);
    previewWanted = true;
    startWebcam(serial, settings, sink, false);
  }
  function startWebcam(serial, settings, sink, restarting) {
    try {
      var args = Webcam.webcamCommand(serial, settings, sink);
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
  // Stops the running session; the status handler runs `launch` once it has
  // ended. Example: switchTo("webcam", "USB123", () => launchWebcam(…)).
  // Only a running session is switched: one still starting (wake/unlock
  // prep, or scrcpy not up yet) would be stopped before it exists, so its
  // own launch would land after the switch and be killed by the next lap.
  // The launcher may still be returning once the session runs; that's fine.
  function switchTo(kind, serial, launch) {
    if (sessionPid <= 0 || preparer.busy)
      return report("Wait until the current session has started.", false, kind === "webcam" ? "webcam" : "mirror");
    if (stopping || pendingSwitch)
      return report("A switch is already in progress.", false, kind === "webcam" ? "webcam" : "mirror");
    pendingSwitch = { kind: kind, serial: serial, launch: launch };
    report("Switching to " + (kind === "webcam" ? "the webcam" : kind === "audio" ? "audio" : "mirroring") + "…", false, kind === "webcam" ? "webcam" : "mirror");
    stopRunning();
  }
  // Apply: the same phone and output, the settings shown when it was pressed.
  function restartWebcam(settings) {
    if (sessionType !== "webcam" || sessionPid <= 0 || pendingSwitch)
      return;
    var serial = sessionSerial;
    var sink = sessionSink;
    switchTo("webcam", serial, () => startWebcam(serial, settings, sink, true));
    report("Restarting the webcam with the new settings…", false, "webcam");
  }
  function runPendingSwitch() {
    var next = pendingSwitch;
    pendingSwitch = null;
    if (!next)
      return;
    // The launch itself reports missing tools, so the switch never hangs.
    next.launch();
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

  // The user's Stop: during a switch it cancels the launch waiting for it.
  function stop() {
    if (pendingSwitch) {
      pendingSwitch = null;
      return report("Switch cancelled.", false);
    }
    stopRunning();
  }
  function stopRunning() {
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
    // Only the webcam this instance just started opens its preview.
    if (!pendingSwitch)
      previewWanted = false;
    // The stopper's own message would land on the new launch; it
    // refreshes once more when it returns.
    if (pendingSwitch) {
      if (!stopper.busy)
        Qt.callLater(runPendingSwitch);
    } else if (lines[1] && sessionType === "webcam" && !stopping && (wasActive || webcamReportDue)) {
      webcamReportDue = false;
      report(lines[1], true, "webcam");
    } else if (wasActive && !stopping && message.indexOf("Session stopped") !== 0 && message.indexOf("Session force-stopped") !== 0) {
      report(endedMessage(), false, sessionKindOfMessage());
    } else if (message.indexOf("Session started") === 0) {
      report("scrcpy exited. Press Log for its output." + recordingNote(), false, sessionKindOfMessage());
    }
  }
  // Audio-only sessions live in the Mirror section.
  function sessionKindOfMessage() {
    return sessionType === "webcam" ? "webcam" : "mirror";
  }
  function recordingNote() {
    return sessionRecording ? " Recording: " + sessionRecording : "";
  }
  function endedMessage() {
    return (sessionType === "webcam" ? "Webcam session ended. Check Log for camera or size errors." : sessionAudioOnly ? "Audio session ended." : "Mirroring ended.") + recordingNote();
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
        root.pendingSwitch = null;
      if (!root.pendingSwitch)
        root.message = root.failed ? Model.commandError(code, output, error, "scrcpy stop") : output.trim();
      root.stopping = false;
      root.refreshSession();
    }
  }
}
