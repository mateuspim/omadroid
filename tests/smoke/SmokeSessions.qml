import QtQuick
import "../.." as OmaDroid

// The session half of tests/Smoke.qml (split to keep both files short):
// real scrcpy launches against tests/mock-scrcpy.sh through the device
// page's session cards. Two widgets show the USB phone, as two monitors
// would, each with its own MirrorSession; a third shows the wireless phone.
//
// Steps (host.step): 7 failed AV1 launch, then profile options; 8 a recorded
// mirror that exits; 9 a mirror that keeps running, the recording confirm,
// a switch to the webcam with its preview, stopped from the other widget;
// 10 webcam options; 11 webcam start and Apply; 12 done.
//
// Public API: host (Smoke's root: step, check(), child()), devices, idle, begin()
Item {
  id: root
  required property var host
  property var devices: []
  property bool switchQueued: false
  property bool stopQueued: false
  property bool webcamApplied: false
  readonly property var first: firstSession
  readonly property var second: secondSession
  readonly property var phone: devices.find(row => row.serial === "USB123") || null
  readonly property bool idle: !firstSession.busy && !secondSession.busy

  // Step 6 is done: a launch with an unavailable codec must fail cleanly.
  function begin() {
    host.step = 7;
    mirroring.mirrorOptions.changeOption("codec", "av1");
    Qt.callLater(() => mirroring.activate("mirror"));
  }
  function card(sessions, kind) {
    return sessions.cards.find(c => c.key === kind);
  }

  OmaDroid.MirrorSession {
    id: firstSession
  }
  OmaDroid.MirrorSession {
    id: secondSession
  }
  OmaDroid.DeviceSessions {
    id: mirroring
    width: 440
    serial: "USB123"
    device: root.phone
    devices: root.devices
    session: firstSession
  }
  OmaDroid.DeviceSessions {
    id: otherMonitor
    width: 440
    serial: "USB123"
    device: root.phone
    devices: root.devices
    session: secondSession
  }
  OmaDroid.DeviceSessions {
    id: wirelessPage
    width: 440
    serial: "adb-PHONE-random._adb-tls-connect._tcp"
    device: root.devices.find(row => row.serial === serial) || null
    devices: root.devices
    session: secondSession
  }
  // A page whose device has gone: its forms must not launch anywhere else.
  OmaDroid.DeviceSessions {
    id: unplugged
    width: 440
    serial: "UNPLUGGED"
    session: firstSession
  }
  Timer {
    id: stopTimer
    interval: 300
    onTriggered: secondSession.stop()
  }

  Timer {
    interval: 200
    running: root.host.step >= 7 && root.host.step < 10
    repeat: true
    onTriggered: {
      var step = root.host.step;
      if (step === 7 && !firstSession.busy && firstSession.message)
        root.saveProfileStep();
      else if (step === 8 && !firstSession.busy && firstSession.sessionRecording.endsWith(".mkv"))
        root.keptMirrorStep();
      else if (step === 9 && !root.switchQueued && firstSession.sessionPid > 0 && secondSession.sessionPid === firstSession.sessionPid)
        root.switchStep();
      else if (step === 9 && root.switchQueued && !root.stopQueued && firstSession.sessionType === "webcam" && firstSession.sessionPid > 0 && secondSession.sessionPid === firstSession.sessionPid)
        root.switchedStep();
      else if (step === 9 && root.stopQueued && root.idle)
        root.stoppedStep();
    }
  }
  function saveProfileStep() {
    var check = host.check;
    // Command items once took layout slots and pushed the content down.
    check(mirroring.children.every(item => !item.visible || item.y === 0 || item.height > 0), "no empty layout slots in the session cards");
    var options = mirroring.mirrorOptions;
    options.changeOption("codec", "h264");
    options.changeOption("audio", false);
    options.changeOption("record", true);
    options.changeOption("screenOff", true);
    options.changeOption("fullscreen", true);
    options.saveProfile("Fixture profile");
    options.selectProfile("Balanced");
    options.selectProfile("Fixture profile");
    check(options.profile.screenOff && !options.profile.audio, "saved profile restores options");
    check(card(mirroring, "mirror").subtitle === "Fixture profile · 1080p · 8 Mbps · Rec", "the Mirror card summarizes the profile: " + card(mirroring, "mirror").subtitle);
    host.step = 8;
    mirroring.activate("mirror");
  }
  function keptMirrorStep() {
    host.check(!firstSession.failed, "scrcpy successful exit: " + firstSession.message);
    host.step = 9;
    mirroring.mirrorOptions.changeOption("fps", "120");
    mirroring.activate("mirror");
  }
  // A recording mirror runs: the session card leads, a click on Webcam asks
  // first, anything else disarms, a second click switches.
  function switchStep() {
    var check = host.check;
    check(firstSession.message.indexOf("Session started") !== 0, "launch message cleared once active: " + firstSession.message);
    check(host.child(mirroring, "omadroidSessionCard").visible && !host.child(mirroring, "omadroidNextOptions").visible, "session card shown, options folded");
    check(card(mirroring, "mirror").running && card(otherMonitor, "mirror").subtitle === "● Running", "both widgets mark the mirror running");
    check(card(wirelessPage, "mirror").subtitle === "Switch · stops Desk phone" && !host.child(wirelessPage, "omadroidSessionCard").visible, "another phone's page offers a switch, no session card");
    mirroring.toggleOptions("mirror");
    check(host.child(mirroring, "omadroidNextOptions").visible && host.child(mirroring, "omadroidSessionCard").visible, "options open during a session");
    mirroring.activate("webcam");
    check(mirroring.armed === "webcam" && firstSession.pendingSwitch === null && card(mirroring, "webcam").subtitle === "Stop recording & switch?", "a recording asks before switching: " + card(mirroring, "webcam").subtitle);
    mirroring.toggleOptions("mirror");
    check(mirroring.armed === "" && firstSession.busy, "anything else disarms");
    mirroring.activate("webcam");
    mirroring.activate("webcam");
    check(firstSession.pendingSwitch !== null && firstSession.pendingSwitch.kind === "webcam", "the second click switches");
    check(card(mirroring, "webcam").subtitle === "Switching…" && !host.child(mirroring, "omadroidNextOptions").visible, "the target card says so, options fold");
    root.switchQueued = true;
  }
  function switchedStep() {
    var check = host.check;
    check(firstSession.sessionArgs.indexOf("--video-source=camera") >= 0 && firstSession.sessionRecording === "", "the webcam replaced the mirror: " + JSON.stringify(firstSession.sessionArgs));
    check(card(mirroring, "webcam").running && card(mirroring, "mirror").subtitle === "Switch · stops the webcam", "the Webcam card runs now");
    check(mirroring.previewOpen && !firstSession.previewWanted, "the widget that started the webcam opens its preview");
    check(!otherMonitor.previewOpen, "another widget doesn't");
    root.stopQueued = true;
    stopTimer.start();
  }
  function stoppedStep() {
    var check = host.check;
    check(!host.child(mirroring, "omadroidSessionCard").visible && mirroring.cards.every(c => c.action === "start"), "idle cards start again");
    host.step = 10;
    unplugged.activate("mirror");
    check(firstSession.failed && !firstSession.busy, "a page whose device is gone cannot launch on another phone");
  }

  Timer {
    interval: 200
    running: root.host.step >= 10 && root.host.step < 12
    repeat: true
    onTriggered: {
      // Opening the Webcam options reads the phone's cameras; wait for them.
      if (root.host.step === 10 && !mirroring.webcamOptions.cameras)
        mirroring.optionsKind = "webcam";
      else if (root.host.step === 10)
        root.webcamOptionsStep();
      else if (root.webcamApplied && firstSession.sessionPid > 0 && secondSession.sessionPid === firstSession.sessionPid && firstSession.sessionArgs.indexOf("--camera-fps=24") >= 0)
        root.appliedStep();
      else if (!root.webcamApplied && firstSession.sessionPid > 0 && secondSession.sessionPid === firstSession.sessionPid)
        root.webcamRunningStep();
    }
  }
  function webcamOptionsStep() {
    var check = host.check;
    var options = mirroring.webcamOptions;
    check(host.child(mirroring, "omadroidWebcamOptions").visible && !host.child(mirroring, "omadroidMirrorResolution").visible, "the Webcam ⚙ shows only camera settings");
    var outputs = options.webcamOutputs;
    options.webcamOutputs = [];
    options.webcamIssue = "missing-package";
    check(host.child(mirroring, "omadroidWebcamSetup").visible, "missing driver shows setup card");
    check(card(mirroring, "webcam").action === "options", "the Webcam card asks for setup first");
    options.copyWebcamCommands();
    options.webcamOutputs = outputs;
    options.webcamIssue = "";
    check(options.webcamSink === "/dev/video12", "the first loopback output is selected: " + options.webcamSink);
    // Panes here sit outside a window, so layouts never re-measure and
    // widths cannot be checked; only that the folded section opens.
    options.webcamDetailsOpen = true;
    check(host.child(mirroring, "omadroidWebcamDetails").visible, "quality and adjustments open");
    // The fixture lists the Tab S11's cameras: front becomes camera 1 and
    // the Call preset's 1080p fits it.
    check(options.cameras && options.cameras.length === 3, "cameras read from the phone: " + JSON.stringify(options.cameras));
    check(options.webcam.camera === "id:1" && options.webcam.size === "1920x1080" && options.webcam.fps === "30", "webcam settings fit the camera: " + JSON.stringify(options.webcam));
    check(card(mirroring, "webcam").subtitle === "Front · 1080p · 30 fps", "the Webcam card names the camera: " + card(mirroring, "webcam").subtitle);
    options.applyPreset("sharp");
    check(options.webcam.size === "2032x1144" && options.webcam.bitRate === "24", "Sharp preset picks the camera's largest 16:9: " + JSON.stringify(options.webcam));
    options.setWebcam({ camera: "id:2" }, true);
    options.applyPreset("sharp");
    check(options.webcam.size === "3840x2160", "camera 2 reaches 4K");
    options.setWebcam({ camera: "id:1", zoom: "2", torch: true }, true);
    options.applyPreset("call");
    host.step = 11;
    mirroring.activate("webcam");
  }
  function webcamRunningStep() {
    var check = host.check;
    // Another widget reads the running command from /proc, as after a
    // shell reload.
    if (JSON.stringify(secondSession.sessionArgs) !== JSON.stringify(firstSession.sessionArgs))
      return;
    check(secondSession.sessionType === "webcam" && firstSession.sessionType === "webcam", "webcam session type shared across widgets");
    check(secondSession.sessionSink === "/dev/video12" && secondSession.sessionRecording === "", "webcam sink shared across widgets: " + secondSession.sessionSink);
    check(firstSession.sessionArgs.indexOf("--camera-id=1") >= 0 && firstSession.sessionArgs.indexOf("--camera-zoom=2") >= 0 && firstSession.sessionArgs.indexOf("--camera-torch") >= 0, "webcam starts with the chosen camera and adjustments: " + JSON.stringify(firstSession.sessionArgs));
    check(!mirroring.webcamOptions.webcamChanged && !otherMonitor.webcamOptions.webcamChanged, "nothing to apply right after start, on either widget: " + JSON.stringify(otherMonitor.webcamOptions.webcam));
    check(host.child(mirroring, "omadroidWebcamPreview").visible, "the preview opens by itself during a webcam session");
    check(host.child(otherMonitor, "omadroidSessionCard").visible && !host.child(wirelessPage, "omadroidSessionCard").visible, "the session card shows on its device's page only");
    mirroring.webcamOptions.setWebcam({ fps: "24" });
    check(mirroring.webcamOptions.webcamChanged && host.child(mirroring, "omadroidWebcamApply").visible, "a changed setting offers Apply");
    root.webcamApplied = true;
    mirroring.webcamOptions.applyWebcam();
  }
  // Apply restarted the webcam with the new rate, and the other widget
  // learned the new command from the running scrcpy.
  function appliedStep() {
    if (JSON.stringify(secondSession.sessionArgs) !== JSON.stringify(firstSession.sessionArgs))
      return;
    host.check(!mirroring.webcamOptions.webcamChanged && !firstSession.restartPending && !otherMonitor.webcamOptions.webcamChanged, "applied settings match the running webcam on both widgets");
    host.step = 12;
    secondSession.stop();
  }
}
