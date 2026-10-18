import QtQuick
import QtTest
import Quickshell
import qs.Commons
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
    property color barForeground: Color.foreground
    property color urgent: Color.urgent
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
    color: Color.popups.background
    Rectangle {
      id: surface
      anchors.centerIn: parent
      width: 460
      height: 900
      color: Color.popups.background
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
      item.parent = mount; widget.toggle();
    }
  }
  Timer {
    interval: 2500
    running: true
    repeat: true
    onTriggered: {
      // OMADROID_PREVIEW_PAGES picks the pages, comma-separated, in order.
      var names = (Quickshell.env("OMADROID_PREVIEW_PAGES") || "devices,wireless,mirror,webcam,sound,settings").split(",");
      if (root.frame >= names.length) {
        console.log("OMADROID_PREVIEW_OK");
        Qt.quit();
        return;
      }
      var name = names[root.frame];
      var item = mount.children[0];
      if (!item) {
        console.error("OMADROID_TEST_FAILED: popup missing");
        Qt.exit(1);
        return;
      }
      if (!surface.grabToImage(function (result) {
        if (!result.saveToFile(Quickshell.env("OMADROID_PREVIEW_DIR") + "/" + name + ".png")) {
          console.error("OMADROID_TEST_FAILED: cannot save capture");
          Qt.exit(1);
          return;
        }
        root.frame++;
        if (root.frame < names.length)
          widget.page = names[root.frame];
      })) {
        console.error("OMADROID_TEST_FAILED: capture failed");
        Qt.exit(1);
      }
    }
  }
}
