import QtQuick
import Quickshell
import "plugin" as OmaDroid
import "plugin/tests/smoke" as SmokeTests

ShellRoot {
  id: testRoot
  property int step: 0
  function check(condition, message) {
    if (!condition) {
      console.error("OMADROID_TEST_FAILED: " + message);
      Qt.exit(1);
    }
  }
  // The visible match wins, else the first (hidden) one.
  function child(item, name) {
    var all = [];
    collect(item, name, all);
    return all.find(found => found.visible) || all[0] || null;
  }
  function collect(item, name, all) {
    for (var i = 0; i < item.children.length; i++) {
      if (item.children[i].objectName === name)
        all.push(item.children[i]);
      collect(item.children[i], name, all);
    }
  }
  // Mirror, audio and webcam sessions through the device page's cards.
  SmokeTests.SmokeSessions {
    id: sessions
    host: testRoot
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
  // Add device against a fake Actions: a device-list Pair opens the
  // pairing-code form prefilled, and only the connect that follows the pair
  // reports done.
  QtObject {
    id: addActions
    property bool busy: false
    property bool failed: false
    property string action: ""
    property string message: ""
    property string pairedAwaitingConnect: ""
    property var discovery: null
    property var calls: []
    signal changed
    function run(kind, address, secret) {
      calls = calls.concat([[kind, address, secret]]);
      return true;
    }
    function finish(kind, ok) {
      action = kind;
      failed = !ok;
      changed();
    }
  }
  OmaDroid.AddDevicePage {
    id: addDevice
    width: 440
    actions: addActions
    property int doneCount: 0
    onDone: doneCount += 1
    Component.onCompleted: {
      beginPair({ endpoint: "192.168.1.5:41000", pair: true }, [], true);
      var form = testRoot.child(addDevice, "omadroidConnectionForm");
      testRoot.check(mode === "code" && form.pairing && form.fixedPairingHost, "Pair from the list opens the pairing-code form: " + mode);
      form.submit();
      testRoot.check(awaitingResult && addActions.calls[0][0] === "pair" && addActions.calls[0][1] === "192.168.1.5:41000", "the form pairs the prefilled host and port: " + JSON.stringify(addActions.calls));
      cancel();
      testRoot.check(!awaitingResult, "leaving the page stops waiting");
      setMode("address");
      testRoot.check(!form.pairing, "Address shows the connect form");
      form.submitted();
      addActions.finish("pair", true);
      testRoot.check(awaitingResult && doneCount === 0, "a pair alone isn't done");
      addActions.finish("connect", true);
      testRoot.check(!awaitingResult && doneCount === 1, "the connect after it is done: " + doneCount);
      addActions.finish("connect", true);
      testRoot.check(doneCount === 1, "results of other actions don't count");
    }
  }
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
        sessions.begin();
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
      testRoot.check(wakeButton && wakeButton.checked, "Settings page shows wake on launch on: " + (wakeButton ? wakeButton.checked : "missing"));
      settingsPane.toggle("wakeOnLaunch");
      testRoot.check(!discovery.preferences.wakeOnLaunch && !wakeButton.checked, "Settings page toggle saved: " + wakeButton.checked);
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
      testRoot.check(testRoot.step === 12 && sessions.idle, "all process checks finished: step=" + testRoot.step + " first=" + sessions.first.sessionPid + "/" + sessions.first.message + " other=" + sessions.second.sessionPid + "/" + sessions.second.message);
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
