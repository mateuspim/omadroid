import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "plugin" as OmaDroid

// Offscreen visual review using the same fake backends as smoke.sh: one PNG
// per page in OMADROID_PREVIEW_DIR, no window on the desktop.
ShellRoot {
  id: root
  property int frame: 0
  TestCase {
    id: finder
    when: false
  }
  // The bar hands the panel the shell-owned discovery service; here a real
  // Discovery runs against the mock adb/avahi in PATH.
  OmaDroid.Discovery {
    id: fakeDiscovery
  }
  QtObject {
    id: fakeShell
    function serviceFor(id) { return fakeDiscovery; }
  }
  QtObject {
    id: fakeBar
    property var shell: fakeShell
    property string position: "top"
    property bool vertical: false
    property int barSize: Style.bar.sizeHorizontal
    property color barForeground: Commons.Color.foreground
    property color urgent: Commons.Color.urgent
    property string fontFamily: Style.font.family
    property bool foregroundAnimationEnabled: false
  }
  OmaDroid.Panel {
    id: widget
    bar: fakeBar
  }
  FloatingWindow {
    id: preview
    title: "OmaDroid · fixture preview"
    implicitWidth: 460
    implicitHeight: 900
    color: Commons.Color.popups.background
    Rectangle {
      id: surface
      anchors.centerIn: parent
      width: 460
      height: 900
      color: Commons.Color.popups.background
      Item {
        id: mount
        anchors.fill: parent
        anchors.margins: 16
      }
    }
  }
  Timer {
    interval: 300
    running: true
    onTriggered: {
      var item = finder.findChild(widget, "omadroidPopup");
      item.parent = mount;
      widget.toggle();
    }
  }
  property bool shown: false
  // A view name: home, add, settings, or device[-<part>] (the USB phone) /
  // wifi[-<part>] (the wireless one), part = sound|info (a section) or
  // mirror|audio|webcam (that card's ⚙ options open).
  // Session steps act on the shown device page: `click-<kind>` clicks a
  // session card (`start` = click-webcam), `record` turns on recording,
  // `wait` captures as is, `stopped` ends the session from home. The mock
  // scrcpy keeps camera sessions running; OMADROID_SCRCPY_STAY=1 keeps
  // mirrors and audio running too.
  function sessions() {
    return finder.findChild(mount, "omadroidDevicePage").sessions;
  }
  function show(name) {
    var steps = {
      start: () => sessions().activate("webcam"),
      record: () => sessions().mirrorOptions.changeOption("record", true),
      wait: () => {},
      stopped: () => {
        widget.go("home");
        Qt.callLater(() => widget.stopSession());
      }
    };
    if (steps[name])
      return steps[name]();
    var parts = name.split("-");
    if (parts[0] === "click")
      return sessions().activate(parts[1]);
    if (parts[0] !== "device" && parts[0] !== "wifi")
      return widget.go(name);
    if (parts[1] === "sound" || parts[1] === "info")
      widget.deviceSection = parts[1];
    widget.go("device", parts[0] === "device" ? "USB123" : "adb-PHONE-random._adb-tls-connect._tcp");
    var kind = ["mirror", "audio", "webcam"].indexOf(parts[1]) >= 0 ? parts[1] : "";
    Qt.callLater(() => sessions().optionsKind = kind);
  }
  // Each view gets one tick to load and settle, the next to be captured.
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: {
      // OMADROID_PREVIEW_PAGES picks the views, comma-separated, in order.
      var names = (Quickshell.env("OMADROID_PREVIEW_PAGES") || "home,device,device-mirror,device-webcam,device-info,wifi-sound,add,settings,device,start,home,stopped").split(",");
      if (root.frame >= names.length) {
        console.log("OMADROID_PREVIEW_OK");
        Qt.quit();
        return;
      }
      var name = names[root.frame];
      if (!root.shown) {
        root.show(name);
        root.shown = true;
        return;
      }
      if (!mount.children[0]) {
        console.error("OMADROID_TEST_FAILED: popup missing");
        Qt.exit(1);
        return;
      }
      if (!surface.grabToImage(function (result) {
        if (!result.saveToFile(Quickshell.env("OMADROID_PREVIEW_DIR") + "/" + root.frame + "-" + name + ".png")) {
          console.error("OMADROID_TEST_FAILED: cannot save capture");
          Qt.exit(1);
          return;
        }
        root.frame++;
        root.shown = false;
      })) {
        console.error("OMADROID_TEST_FAILED: capture failed");
        Qt.exit(1);
      }
    }
  }
}
