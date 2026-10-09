import QtQuick
import Quickshell
import "plugin" as DroidLink

ShellRoot {
  id: testRoot
  property int step: 0
  property bool stopQueued: false
  function check(condition, message) {
    if (!condition) {
      console.error("DROIDLINK_TEST_FAILED: " + message);
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
  DroidLink.ScrcpyPane {
    id: mirroring
    width: 440
    devices: discovery.devices
  }
  DroidLink.DevicePowerControls {
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
  DroidLink.QrPairing {
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
  DroidLink.SettingsPane {
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
  DroidLink.AutoConnect {
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
  DroidLink.ScrcpyPane {
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
        testRoot.check(child(mirroring, "droidlinkSessionCard").visible && !child(mirroring, "droidlinkNextOptions").visible, "session card first, options folded");
        mirroring.optionsExpanded = true;
        testRoot.check(child(mirroring, "droidlinkNextOptions").visible, "options expand during a session");
        testRoot.stopQueued = true;
        stopTimer.start();
      } else if (testRoot.step === 9 && testRoot.stopQueued && !mirroring.busy && !otherMonitor.busy) {
        testRoot.check(!child(mirroring, "droidlinkSessionCard").visible && child(mirroring, "droidlinkNextOptions").visible, "options shown when idle");
        testRoot.step = 10;
        mirroring.chooseDevice("UNPLUGGED");
        mirroring.launch();
        testRoot.check(mirroring.failed && !mirroring.busy, "stale selection cannot launch on a different phone");
      }
    }
  }
  DroidLink.Discovery {
    id: discovery
    mdnsInBackground: true
    onBusyChanged: if (!busy && initialized) {
      Qt.callLater(function () {
        testRoot.check(discovery.devices.length === 4, "four adb devices");
        var unavailable = Quickshell.env("DROIDLINK_TEST_CASE") === "avahi_unavailable";
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
  DroidLink.Actions {
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
  DroidLink.Command {
    id: command
    onFinished: (code, output, error) => {
      if (testRoot.step === 5) {
        testRoot.check(code === 124, "command timeout");
        testRoot.step = 6;
        Qt.callLater(() => command.start(["droidlink-intentionally-missing-executable"], 2));
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
  // Mirrors stop at step 10; mDNS settles for 1.5 s before the first step.
  Timer {
    interval: 9000
    running: true
    onTriggered: {
      var named = discovery.devices.find(row => row.serial === "USB123");
      testRoot.check(named && named.name === "Desk phone" && named.model === "Pixel 6", "Android device name replaces the model: " + JSON.stringify(named));
      testRoot.check(discovery.devices.find(row => row.serial === "adb-PHONE-random._adb-tls-connect._tcp").name === "Pixel 9", "a device without a name keeps its model");
      testRoot.check(named.info && named.info.battery.level === 64 && named.info.external.length === 1, "device details are read: " + JSON.stringify(named.info));
      testRoot.check(discovery.devices.find(row => row.serial === "adb-PHONE-random._adb-tls-connect._tcp").info === null, "a device that doesn't answer has no details");
      testRoot.check(discovery.devices.find(row => row.serial === "LOCKED").info === null, "unauthorized devices aren't queried");
      testRoot.check(powerControls.power && !powerControls.power.keepAwake && powerControls.power.secret === "none" && powerControls.canUnlock === false, "device power status is read: " + JSON.stringify(powerControls.power));
      // The Settings page shows and flips the shared service's options.
      var wakeButton = child(settingsPane, "droidlinkSetting-wakeOnLaunch");
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
      testRoot.check(testRoot.step === 10, "all process checks finished: step=" + testRoot.step + " first=" + mirroring.sessionPid + "/" + mirroring.message + " other=" + otherMonitor.sessionPid + "/" + otherMonitor.message);
      console.log("DROIDLINK_SMOKE_OK");
      Qt.quit();
    }
  }
}
