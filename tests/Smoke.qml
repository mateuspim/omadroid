import QtQuick
import Quickshell
import "plugin" as DroidLink

ShellRoot {
  id: testRoot
  property int step: 0
  function check(condition, message) {
    if (!condition) {
      console.error("DROIDLINK_TEST_FAILED: " + message);
      Qt.exit(1);
    }
  }
  DroidLink.Panel {
    id: panel
  }
  DroidLink.ScrcpyPane {
    id: mirroring
    width: 440
    devices: discovery.devices
    onBusyChanged: if (!busy)
      Qt.callLater(function () {
        if (testRoot.step === 7) {
          testRoot.check(mirroring.failed && mirroring.message.indexOf("AV1 encoder") >= 0, "scrcpy errors reach the popup");
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
        } else if (testRoot.step === 8) {
          testRoot.check(!mirroring.failed, "scrcpy successful exit");
          testRoot.check(mirroring.sessionRecording.endsWith(".mkv"), "recording path retained");
          testRoot.step = 9;
          mirroring.changeOption("fps", "120");
          mirroring.launch();
          stopTimer.start();
        } else if (testRoot.step === 9) {
          testRoot.check(!mirroring.failed, "SIGINT gracefully ends scrcpy");
          testRoot.step = 10;
          mirroring.chooseDevice("UNPLUGGED");
          mirroring.launch();
          testRoot.check(mirroring.failed && !mirroring.busy, "stale selection cannot launch on a different phone");
        }
      })
  }
  DroidLink.Discovery {
    id: discovery
    onBusyChanged: if (!busy && initialized) {
      Qt.callLater(function () {
        testRoot.check(discovery.devices.length === 4, "four adb devices");
        var unavailable = Quickshell.env("DROIDLINK_TEST_CASE") === "avahi_unavailable";
        testRoot.check(discovery.rows.length === (unavailable ? 4 : 6), "merged mDNS rows");
        testRoot.check(unavailable ? discovery.mdnsError.indexOf("Daemon not running") >= 0 : !discovery.mdnsError, "mDNS failure does not suppress USB");
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
    onTriggered: mirroring.stop()
  }
  Timer {
    interval: 3500
    running: true
    onTriggered: {
      testRoot.check(testRoot.step === 10, "all process checks finished");
      console.log("DROIDLINK_SMOKE_OK");
      Qt.quit();
    }
  }
}
