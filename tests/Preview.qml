import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "plugin" as OmaDroid

// Optional short-lived visual review using the same fake backends as smoke.sh.
ShellRoot {
  id: root
  property int frame: 0
  TestCase {
    id: finder
    when: false
  }
  OmaDroid.Panel {
    id: widget
  }
  FloatingWindow {
    id: preview
    title: "OmaDroid · fixture preview"
    implicitWidth: 460
    implicitHeight: 650
    color: Color.popups.background
    Rectangle {
      id: surface
      anchors.centerIn: parent
      width: 460
      height: 650
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
      item.parent = mount;
    }
  }
  Timer {
    interval: 700
    running: true
    repeat: true
    onTriggered: {
      var names = ["devices", "wireless", "mirror", "webcam"];
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
