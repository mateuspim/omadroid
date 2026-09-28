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
        testRoot.check(!mirroring.failed, "scrcpy successful exit");
        testRoot.step = 9;
        mirroring.changeOption("fps", "120");
        mirroring.launch();
      } else if (testRoot.step === 9 && mirroring.sessionPid > 0 && otherMonitor.sessionPid === mirroring.sessionPid && !testRoot.stopQueued) {
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
  Timer {
    interval: 5000
    running: true
    onTriggered: {
      testRoot.check(testRoot.step === 10, "all process checks finished: step=" + testRoot.step + " first=" + mirroring.sessionPid + "/" + mirroring.message + " other=" + otherMonitor.sessionPid + "/" + otherMonitor.message);
      console.log("DROIDLINK_SMOKE_OK");
      Qt.quit();
    }
  }
}
