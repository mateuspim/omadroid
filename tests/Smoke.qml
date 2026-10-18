import QtQuick
import Quickshell
import "plugin" as OmaDroid

ShellRoot {
  id: testRoot
  property int step: 0
  property bool stopQueued: false
  property bool webcamApplied: false
  function check(condition, message) {
    if (!condition) {
      console.error("OMADROID_TEST_FAILED: " + message);
      Qt.exit(1);
    }
  }
  function child(item, name) {
    for (var i = 0; i < item.children.length; i++) {
      var found = item.children[i].objectName === name ? item.children[i] : child(item.children[i], name);
      if (found)
        return found;
    }
    return null;
  }
  OmaDroid.ScrcpyPane {
    id: mirroring
    width: 440
    devices: discovery.devices
  }
  // Loaded only on demand in the panel; instantiated here so a QML error in
  // either fails the smoke test. No device, so no camera opens.
  OmaDroid.WebcamPreview {
    id: previewCheck
    width: 320
  }
  OmaDroid.PreviewSplash {
    id: splashCheck
    width: 320
    height: 180
    label: "Waiting"
  }
  // Sound page against tests/mock-volume-adb.sh: the game playing at 10/100.
  OmaDroid.SoundPane {
    id: soundPane
    width: 440
    devices: discovery.devices
    active: true
  }
  Timer {
    interval: 9000
    running: true
    onTriggered: {
      testRoot.check(soundPane.volume && soundPane.volume.mode === "samsung" && soundPane.readError === "", "sound status read: " + JSON.stringify(soundPane.volume) + " " + soundPane.readError);
      var game = soundPane.apps.find(app => app.uid === 10360);
      testRoot.check(game && game.label === "Honkai: Star Rail" && game.volume === 10 && testRoot.child(soundPane, "soundApp:10360") !== null, "the playing game has a row: " + JSON.stringify(soundPane.apps));
      testRoot.check(testRoot.child(soundPane, "soundStream:media") !== null, "media has a row");
      // A new reading moves the sliders; rebuilding them broke a drag.
      var row = testRoot.child(soundPane, "soundApp:10360");
      soundPane.volume = JSON.parse(JSON.stringify(soundPane.volume));
      testRoot.check(testRoot.child(soundPane, "soundApp:10360") === row, "rows survive a new reading");
      soundPane.setApp(game, 35);
      soundPane.setApp(game, 40);
      testRoot.check(soundPane.apps.find(app => app.uid === 10360).volume === 40, "a change shows at once");
      soundPane.toggleStream(soundPane.volume.streams.find(stream => stream.key === "media"));
      // Clicked like a person would: the handler once sent the opposite command.
      testRoot.child(soundPane, "soundMuteAll").clicked();
      testRoot.check(soundPane.volume.master === true, "Mute all shows at once");
    }
  }
  OmaDroid.DevicePowerControls {
    id: powerControls
    width: 440
    serial: "USB123"
    ready: true
  }
  // QR pairing against a fake actions object: pairing must wait for the
  // scanned code's own service, then send its password once.
  QtObject {
    id: qrActions
    property bool busy: false
    property var discovery: QtObject {
      property var rows: [{ pair: true, serial: "adb-OTHER-pair", endpoint: "192.168.1.9:40000" }]
      property string mdnsLevel: ""
    }
    property var pairCalls: []
    function run(kind, address, secret) {
      pairCalls = pairCalls.concat([[kind, address, secret]]);
      return true;
    }
  }
  OmaDroid.QrPairing {
    id: qrPairing
    width: 440
    actions: qrActions
    Component.onCompleted: show()
    onCodeChanged: if (code) {
      testRoot.qrPassword = code.password;
      testRoot.check(code.size === 3 && qrActions.pairCalls.length === 0, "QR code shown, nothing paired yet");
      qrActions.discovery.rows = qrActions.discovery.rows.concat([{ pair: true, serial: code.service, endpoint: "192.168.1.5:42000" }]);
    }
  }
  property string qrPassword: ""
  OmaDroid.SettingsPane {
    id: settingsPane
    width: 440
    consumer: QtObject {
      readonly property var discovery: discovery
      function setAutoConnect(on) { discovery.setAutoConnect(on); }
      function setPreference(name, value) { discovery.setPreference(name, value); }
    }
  }
  // Auto-connect: two phones are ready over Wi-Fi and get remembered, then
  // both drop. The trusted one is reconnected; the one that refuses (fake adb:
  // 192.168.1.66) is forgotten. Neither endpoint is tried twice.
  OmaDroid.AutoConnect {
    id: autoConnect
    property var attempts: []
    property int stage: 0
    Component.onCompleted: setEnabled(true)
    services: [
      { serial: "adb-TRUSTED-a1", service: "_adb-tls-connect._tcp", endpoint: "192.168.1.5:37002", pair: false },
      { serial: "adb-REFUSES-b2", service: "_adb-tls-connect._tcp", endpoint: "192.168.1.66:37003", pair: false }
    ]
    devices: [
      { serial: "192.168.1.5:37002", status: "device", transport: "Wireless", endpoint: "192.168.1.5:37002" },
      { serial: "192.168.1.66:37003", status: "device", transport: "Wireless", endpoint: "192.168.1.66:37003" }
    ]
    onAttempted: endpoint => attempts = attempts.concat([endpoint])
  }
  Timer {
    interval: 200
    running: autoConnect.stage < 3
    repeat: true
    onTriggered: {
      if (autoConnect.stage === 0) {
        testRoot.check(JSON.stringify(autoConnect.known) === JSON.stringify(["adb-TRUSTED", "adb-REFUSES"]) && autoConnect.attempts.length === 0, "ready phones remembered, none connected: " + JSON.stringify(autoConnect.known));
        autoConnect.devices = [];
        autoConnect.stage = 1;
      } else if (autoConnect.stage === 1 && autoConnect.attempts.length === 2 && JSON.stringify(autoConnect.known) === JSON.stringify(["adb-TRUSTED"])) {
        // The same announcements again must not retry either endpoint.
        autoConnect.services = autoConnect.services.slice();
        autoConnect.stage = 2;
      } else if (autoConnect.stage === 2) {
        testRoot.check(JSON.stringify(autoConnect.attempts) === JSON.stringify(["192.168.1.5:37002", "192.168.1.66:37003"]), "each endpoint tried once: " + JSON.stringify(autoConnect.attempts));
        autoConnect.stage = 3;
      }
    }
  }
  OmaDroid.ScrcpyPane {
    id: otherMonitor
    width: 440
    devices: discovery.devices
  }
  Timer {
    interval: 200
    running: testRoot.step >= 7 && testRoot.step < 10
    repeat: true
    onTriggered: {
      if (testRoot.step === 7 && !mirroring.busy && mirroring.message) {
        // Command items once took layout slots and pushed the heading down.
        testRoot.check(mirroring.children.every(item => !item.visible || item.y === 0 || item.height > 0), "no empty layout slots above the mirror heading");
        mirroring.changeOption("codec", "h264");
        mirroring.changeOption("audio", false);
        mirroring.changeOption("record", true);
        mirroring.changeOption("screenOff", true);
        mirroring.changeOption("fullscreen", true);
        mirroring.saveProfile("Fixture profile");
        mirroring.selectProfile("Balanced");
        mirroring.selectProfile("Fixture profile");
        testRoot.check(mirroring.profile.screenOff && !mirroring.profile.audio, "saved profile restores options");
        testRoot.step = 8;
        mirroring.launch();
      } else if (testRoot.step === 8 && !mirroring.busy && mirroring.sessionRecording.endsWith(".mkv")) {
        testRoot.check(!mirroring.failed, "scrcpy successful exit: " + mirroring.message);
        testRoot.step = 9;
        mirroring.changeOption("fps", "120");
        mirroring.launch();
      } else if (testRoot.step === 9 && mirroring.sessionPid > 0 && otherMonitor.sessionPid === mirroring.sessionPid && !testRoot.stopQueued) {
        testRoot.check(mirroring.message.indexOf("Session started") !== 0, "launch message cleared once active: " + mirroring.message);
        testRoot.check(child(mirroring, "omadroidSessionCard").visible && !child(mirroring, "omadroidNextOptions").visible, "session card first, options folded");
        mirroring.pageMode = "webcam";
        testRoot.check(!child(mirroring, "omadroidSessionCard").visible && child(mirroring, "omadroidOtherSession").visible && child(mirroring, "omadroidWebcamOptions").visible, "webcam page keeps camera settings visible during mirroring");
        mirroring.pageMode = "mirror";
        mirroring.optionsExpanded = true;
        testRoot.check(child(mirroring, "omadroidNextOptions").visible, "options expand during a session");
        testRoot.stopQueued = true;
        stopTimer.start();
      } else if (testRoot.step === 9 && testRoot.stopQueued && !mirroring.busy && !otherMonitor.busy) {
        testRoot.check(!child(mirroring, "omadroidSessionCard").visible && child(mirroring, "omadroidNextOptions").visible, "options shown when idle");
        testRoot.step = 10;
        mirroring.chooseDevice("UNPLUGGED");
        mirroring.launch();
        testRoot.check(mirroring.failed && !mirroring.busy, "stale selection cannot launch on a different phone");
      }
    }
  }
  OmaDroid.Discovery {
    id: discovery
    mdnsInBackground: true
    onBusyChanged: if (!busy && initialized) {
      Qt.callLater(function () {
        testRoot.check(discovery.devices.length === 4, "four adb devices");
        var unavailable = Quickshell.env("OMADROID_TEST_CASE") === "avahi_unavailable";
        testRoot.check(discovery.rows.length === (unavailable ? 4 : 6), "merged mDNS rows");
        testRoot.check(unavailable ? discovery.mdnsLevel === "error" && discovery.mdnsDetails.indexOf("Daemon not running") >= 0 : !discovery.mdnsError, "mDNS failure does not suppress USB");
        testRoot.check(discovery.readyCount === 2, "ready count");
        if (testRoot.step === 0) {
          testRoot.step = 1;
          actions.run("connect", "fail.local:5555", "");
        }
      });
    }
  }
  OmaDroid.Actions {
    id: actions
    onChanged: {
      if (testRoot.step === 1) {
        testRoot.check(failed, "nonzero-independent ADB failure detection");
        testRoot.step = 2;
        Qt.callLater(() => actions.run("pair", "phone.local:42000", "123456"));
      } else if (testRoot.step === 2) {
        testRoot.check(!failed, "pairing code sent over stdin");
        testRoot.check(message.indexOf("123456") === -1, "pairing code absent from message");
        testRoot.step = 3;
        Qt.callLater(() => actions.run("connect", "phone.local:37001", ""));
      } else if (testRoot.step === 3) {
        testRoot.check(!failed, "explicit connect");
        testRoot.step = 4;
        Qt.callLater(() => actions.run("disconnect", "phone.local:37001", ""));
      } else if (testRoot.step === 4) {
        testRoot.check(!failed, "targeted disconnect");
        testRoot.step = 5;
        Qt.callLater(() => command.start(["sleep", "3"], 1));
      }
    }
  }
  OmaDroid.Command {
    id: command
    onFinished: (code, output, error) => {
      if (testRoot.step === 5) {
        testRoot.check(code === 124, "command timeout");
        testRoot.step = 6;
        Qt.callLater(() => command.start(["omadroid-intentionally-missing-executable"], 2));
      } else if (testRoot.step === 6) {
        testRoot.check(code === 127, "missing executable");
        testRoot.step = 7;
        mirroring.chooseDevice("USB123");
        mirroring.changeOption("codec", "av1");
        Qt.callLater(() => mirroring.launch());
      }
    }
  }
  Timer {
    id: stopTimer
    interval: 300
    onTriggered: otherMonitor.stop()
  }
  Timer {
    interval: 200
    running: testRoot.step >= 10 && testRoot.step < 12
    repeat: true
    onTriggered: {
      // Opening the Webcam page reads the phone's cameras; wait for them.
      if (testRoot.step === 10 && !mirroring.cameras) {
        mirroring.chooseDevice("USB123");
        mirroring.pageMode = "webcam";
        return;
      }
      if (testRoot.step === 10) {
        mirroring.pageMode = "webcam";
        testRoot.check(child(mirroring, "omadroidWebcamOptions").visible && !child(mirroring, "omadroidMirrorResolution").visible && !child(mirroring, "omadroidMirrorLaunch").visible, "webcam page shows only camera settings");
        var outputs = mirroring.webcamOutputs;
        mirroring.webcamOutputs = [];
        mirroring.webcamIssue = "missing-package";
        testRoot.check(child(mirroring, "omadroidWebcamSetup").visible, "missing driver shows setup card");
        mirroring.copyWebcamCommands();
        mirroring.webcamOutputs = outputs;
        mirroring.chooseDevice("USB123");
        testRoot.check(mirroring.webcamSink === "/dev/video12", "the first loopback output is selected: " + mirroring.webcamSink);
        mirroring.webcamSink = "/dev/video12";
        // The fixture lists the Tab S11's cameras: front becomes camera 1 and
        // the Call preset's 1080p fits it.
        // Panes here sit outside a window, so layouts never re-measure and
        // widths cannot be checked; only that the folded section opens.
        mirroring.webcamDetailsOpen = true;
        testRoot.check(child(mirroring, "omadroidWebcamDetails").visible, "quality and adjustments open");
        testRoot.check(mirroring.cameras && mirroring.cameras.length === 3, "cameras read from the phone: " + JSON.stringify(mirroring.cameras));
        testRoot.check(mirroring.webcam.camera === "id:1" && mirroring.webcam.size === "1920x1080" && mirroring.webcam.fps === "30", "webcam settings fit the camera: " + JSON.stringify(mirroring.webcam));
        mirroring.applyPreset("sharp");
        testRoot.check(mirroring.webcam.size === "2032x1144" && mirroring.webcam.bitRate === "24", "Sharp preset picks the camera's largest 16:9: " + JSON.stringify(mirroring.webcam));
        mirroring.setWebcam({ camera: "id:2" }, true);
        mirroring.applyPreset("sharp");
        testRoot.check(mirroring.webcam.size === "3840x2160", "camera 2 reaches 4K");
        mirroring.setWebcam({ camera: "id:1", zoom: "2", torch: true }, true);
        mirroring.applyPreset("call");
        testRoot.step = 11;
        mirroring.launchWebcam();
      } else if (testRoot.webcamApplied && mirroring.sessionPid > 0 && otherMonitor.sessionPid === mirroring.sessionPid && mirroring.sessionArgs.indexOf("--camera-fps=24") >= 0) {
        // Apply restarted the webcam with the new rate, and the other widget
        // learned the new command from the running scrcpy.
        if (JSON.stringify(otherMonitor.sessionArgs) !== JSON.stringify(mirroring.sessionArgs))
          return;
        testRoot.check(!mirroring.webcamChanged && !mirroring.restartPending && !otherMonitor.webcamChanged, "applied settings match the running webcam on both widgets");
        testRoot.step = 12;
        otherMonitor.stop();
      } else if (!testRoot.webcamApplied && mirroring.sessionPid > 0 && otherMonitor.sessionPid === mirroring.sessionPid) {
        // Another widget reads the running command from /proc, as after a
        // shell reload.
        if (JSON.stringify(otherMonitor.sessionArgs) !== JSON.stringify(mirroring.sessionArgs))
          return;
        testRoot.check(otherMonitor.sessionType === "webcam" && mirroring.sessionType === "webcam", "webcam session type shared across widgets");
        testRoot.check(otherMonitor.sessionSink === "/dev/video12" && otherMonitor.sessionRecording === "", "webcam sink shared across widgets: " + otherMonitor.sessionSink);
        testRoot.check(mirroring.sessionArgs.indexOf("--camera-id=1") >= 0 && mirroring.sessionArgs.indexOf("--camera-zoom=2") >= 0 && mirroring.sessionArgs.indexOf("--camera-torch") >= 0, "webcam starts with the chosen camera and adjustments: " + JSON.stringify(mirroring.sessionArgs));
        testRoot.check(!mirroring.webcamChanged && !otherMonitor.webcamChanged, "nothing to apply right after start, on either widget: " + JSON.stringify(otherMonitor.webcam));
        mirroring.webcamPreview = true;
        testRoot.check(child(mirroring, "omadroidWebcamPreview").visible, "Preview shows during a webcam session");
        testRoot.check(!child(otherMonitor, "omadroidSessionCard").visible && child(otherMonitor, "omadroidOtherSession").visible && child(otherMonitor, "omadroidNextOptions").visible, "mirror page keeps its options visible during webcam capture");
        mirroring.setWebcam({ fps: "24" });
        testRoot.check(mirroring.webcamChanged && child(mirroring, "omadroidWebcamApply").visible, "a changed setting offers Apply");
        testRoot.webcamApplied = true;
        mirroring.applyWebcam();
      }
    }
  }
  // Send text overlay against the test discovery: two ready phones, ←/→
  // switches between them, non-ASCII is refused, a send remembers the phone.
  readonly property var testDiscovery: discovery
  property int sendTextHides: 0
  property bool sendTextDone: false
  // SendText.qml's window needs Wayland layer shell, so the card is tested alone.
  OmaDroid.SendTextCard {
    id: sendTextOverlay
    property bool opened: false
    function open() { opened = true; reset(); }
    function close() { opened = false; }
    width: 420
    // A `discovery: discovery` property would bind to itself, not the service.
    consumer: QtObject {
      readonly property var discovery: testRoot.testDiscovery
      function setPreference(name, value) { testRoot.testDiscovery.setPreference(name, value); }
    }
    onDismissed: {
      testRoot.sendTextHides += 1;
      close();
    }
  }
  Timer {
    interval: 6000
    running: true
    onTriggered: {
      var hotkey = child(settingsPane, "omadroidHotkey");
      testRoot.check(hotkey.installed === "", "no Send text hotkey at first: " + hotkey.installed + " " + hotkey.message);
      hotkey.run(["set", "super+alt+d"]);
      child(powerControls, "powerLock").clicked();
      sendTextOverlay.open("");
      testRoot.check(sendTextOverlay.opened && sendTextOverlay.target === "USB123", "first ready phone targeted: " + sendTextOverlay.target);
      sendTextOverlay.chooseNext(1);
      testRoot.check(sendTextOverlay.target === "adb-PHONE-random._adb-tls-connect._tcp", "→ picks the next phone: " + sendTextOverlay.target);
      sendTextOverlay.chooseNext(1);
      testRoot.check(sendTextOverlay.target === "USB123", "→ wraps around");
      sendTextOverlay.chooseNext(-1);
      sendTextOverlay.typeText("café");
      testRoot.check(!sendTextOverlay.canSend && sendTextOverlay.warning.indexOf("é") >= 0, "non-ASCII refused: " + sendTextOverlay.warning);
      // Pressed keys become chips; the prompt keeps Backspace unless Ctrl+K comes first.
      var press = (key, modifiers, text) => sendTextOverlay.handleKey({ key: key, modifiers: modifiers || 0, text: text || "" });
      press(Qt.Key_Escape);
      testRoot.check(sendTextOverlay.steps.length === 0 && sendTextOverlay.opened, "Esc clears first");
      press(Qt.Key_A, Qt.ControlModifier);
      press(Qt.Key_K, Qt.ControlModifier);
      press(Qt.Key_Control, Qt.ControlModifier);
      testRoot.check(sendTextOverlay.literalNext, "a lone modifier waits for the key");
      press(Qt.Key_Backspace);
      sendTextOverlay.typeText("it's {ok}");
      press(Qt.Key_Tab);
      press(Qt.Key_Backspace);
      testRoot.check(JSON.stringify(sendTextOverlay.steps) === JSON.stringify([{ key: "ctrl+a" }, { key: "backspace" }, { text: "it's {ok}" }]), "keys recorded as steps: " + JSON.stringify(sendTextOverlay.steps));
      testRoot.check(child(sendTextOverlay, "sendTextKey:ctrl+a") !== null, "a key shows as a chip");
      press(Qt.Key_Return, Qt.ShiftModifier);
      testRoot.check(sendTextOverlay.status.indexOf("Typing on Pixel 9") === 0, "typing status names the phone: " + sendTextOverlay.status);
    }
  }
  Connections {
    target: sendTextOverlay
    function onOpenedChanged() {
      // The reopen and close below fire this again.
      if (sendTextOverlay.opened || testRoot.sendTextDone)
        return;
      testRoot.sendTextDone = true;
      testRoot.check(testRoot.sendTextHides === 1 && !sendTextOverlay.status.startsWith("⚠"), "overlay closes after typing: " + sendTextOverlay.status);
      testRoot.check(discovery.preferences.lastTextTarget === "adb-PHONE-random._adb-tls-connect._tcp", "the phone typed on is remembered");
      sendTextOverlay.open("");
      testRoot.check(sendTextOverlay.target === "adb-PHONE-random._adb-tls-connect._tcp" && sendTextOverlay.steps.length === 0, "reopening preselects it with an empty prompt");
      sendTextOverlay.close();
    }
  }
  // mDNS settles for 1.5 s before the first step.
  Timer {
    interval: 13000
    running: true
    onTriggered: {
      var named = discovery.devices.find(row => row.serial === "USB123");
      testRoot.check(named && named.name === "Desk phone" && named.model === "Pixel 6", "Android device name replaces the model: " + JSON.stringify(named));
      testRoot.check(discovery.devices.find(row => row.serial === "adb-PHONE-random._adb-tls-connect._tcp").name === "Pixel 9", "a device without a name keeps its model");
      testRoot.check(named.info && named.info.battery.level === 64 && named.info.external.length === 1, "device details are read: " + JSON.stringify(named.info));
      testRoot.check(discovery.devices.find(row => row.serial === "adb-PHONE-random._adb-tls-connect._tcp").info === null, "a device that doesn't answer has no details");
      testRoot.check(discovery.devices.find(row => row.serial === "LOCKED").info === null, "unauthorized devices aren't queried");
      testRoot.check(powerControls.power && !powerControls.power.keepAwake && powerControls.power.secret === "none" && powerControls.canUnlock === false, "device power status is read: " + JSON.stringify(powerControls.power));
      var powerRow = child(powerControls, "powerButtons");
      testRoot.check(powerRow.implicitWidth <= powerControls.width, "power buttons fit the card: " + powerRow.implicitWidth + " > " + powerControls.width);
      testRoot.check(powerControls.message === "Device locked." && !powerControls.failed, "Lock reaches the device: " + powerControls.message);
      // The Settings page shows and flips the shared service's options.
      var wakeButton = child(settingsPane, "omadroidSetting-wakeOnLaunch");
      testRoot.check(wakeButton && wakeButton.text.indexOf("✓") === 0, "Settings page shows wake on launch on: " + (wakeButton ? wakeButton.text : "missing"));
      settingsPane.toggle("wakeOnLaunch");
      testRoot.check(!discovery.preferences.wakeOnLaunch && wakeButton.text.indexOf("○") === 0, "Settings page toggle saved: " + wakeButton.text);
      settingsPane.toggle("wakeOnLaunch");
      // Settings page options: saved by the shared service, clamped and coerced.
      discovery.setPreference("refreshIntervalSec", "2");
      testRoot.check(discovery.preferences.refreshIntervalSec === 5 && discovery.intervalSec === 5, "refresh interval clamped to 5 s: " + discovery.intervalSec);
      discovery.setPreference("refreshIntervalSec", 99999);
      testRoot.check(discovery.preferences.refreshIntervalSec === 3600, "refresh interval clamped to 3600 s");
      testRoot.check(discovery.preferences.wakeOnLaunch === true && !discovery.wakeOnConnect, "0.7.0 defaults: wake on launch only");
      discovery.setPreference("unlockOnConnect", 1);
      testRoot.check(discovery.unlockOnConnect === true && discovery.preferences.unlockOnConnect === true, "unlock on connect reaches the service");
      discovery.setPreference("unlockOnConnect", false);
      var unknownRejected = false;
      try {
        discovery.setPreference("deleteEverything", true);
      } catch (e) {
        unknownRejected = e.message.indexOf("deleteEverything") >= 0;
      }
      testRoot.check(unknownRejected, "an unknown preference is rejected by name");
      testRoot.check(autoConnect.stage === 3, "auto-connect finished: stage " + autoConnect.stage + " attempts " + JSON.stringify(autoConnect.attempts) + " known " + JSON.stringify(autoConnect.known));
      testRoot.check(qrActions.pairCalls.length === 1 && JSON.stringify(qrActions.pairCalls[0]) === JSON.stringify(["pair", "192.168.1.5:42000", testRoot.qrPassword]) && qrPairing.code === null, "QR pairing pairs the announced service once: " + JSON.stringify(qrActions.pairCalls));
      testRoot.check(testRoot.step === 12 && !mirroring.busy && !otherMonitor.busy, "all process checks finished: step=" + testRoot.step + " first=" + mirroring.sessionPid + "/" + mirroring.message + " other=" + otherMonitor.sessionPid + "/" + otherMonitor.message);
      testRoot.check(previewCheck.streamFormat === "" && previewCheck.error === "" && previewCheck.implicitHeight > 0, "webcam preview loads idle");
      testRoot.check(splashCheck.shown && splashCheck.progress > 0, "preview splash animates: " + splashCheck.progress);
      testRoot.check(testRoot.sendTextDone, "send text finished");
      var gameNow = soundPane.volume.apps.find(app => app.uid === 10360);
      testRoot.check(gameNow.volume === 40 && soundPane.volume.streams.find(stream => stream.key === "media").muted && soundPane.volume.master === true && soundPane.changeError === "", "sound changes reached the device: " + JSON.stringify(gameNow) + " " + soundPane.changeError);
      var hotkeyRow = child(settingsPane, "omadroidHotkey");
      testRoot.check(hotkeyRow.installed === "SUPER + ALT + D" && child(hotkeyRow, "omadroidHotkeyRemove").visible, "Send text hotkey installed: " + hotkeyRow.installed + " " + hotkeyRow.message);
      console.log("OMADROID_SMOKE_OK");
      Qt.quit();
    }
  }
}
