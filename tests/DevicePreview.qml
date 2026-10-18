import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "plugin" as OmaDroid

// Offscreen review of DevicePage against the fake Discovery of smoke.sh: one
// PNG per device and section in OMADROID_PREVIEW_DIR, no window on the
// desktop. Run with
//   OMADROID_PREVIEW_DIR=<dir> OMADROID_PREVIEW_QML=tests/DevicePreview.qml bash tests/smoke.sh
// OMADROID_PREVIEW_PAGES picks frames, comma-separated, e.g. "usb-info,wifi-sound".
ShellRoot {
  id: root
  property int frame: 0
  // Frames named <device>-<section>-<click> first click that objectName, then
  // capture on the next tick: "usb-info-unlockPinEdit" opens the PIN editor,
  // "usb-sound-sessionOptions:mirror" the Mirror card's options.
  property bool clicked: false
  readonly property var devicesBySlug: ({ usb: "USB123", wifi: "adb-PHONE-random._adb-tls-connect._tcp", locked: "LOCKED" })
  readonly property var frames: (Quickshell.env("OMADROID_PREVIEW_PAGES") || "usb-sound,usb-info,usb-info-unlockPinEdit,usb-sound-deviceControl:lock,usb-sound-sessionOptions:mirror,wifi-sound,wifi-info,locked-info").split(",")
  readonly property string frameName: frames[Math.min(frame, frames.length - 1)]
  readonly property string currentSerial: devicesBySlug[frameName.split("-")[0]] || ""
  readonly property var currentRow: fakeDiscovery.rows.find(row => row.serial === currentSerial) || null

  TestCase {
    id: finder
    when: false
  }
  OmaDroid.Discovery {
    id: fakeDiscovery
    // Device info is read only while a popup holds discovery open.
    Component.onCompleted: holdMdns(root, true)
  }
  OmaDroid.Actions {
    id: fakeActions
    discovery: fakeDiscovery
  }
  OmaDroid.MirrorSession {
    id: fakeSession
  }
  FloatingWindow {
    implicitWidth: 460
    implicitHeight: 900
    color: Commons.Color.popups.background
    Rectangle {
      id: surface
      anchors.centerIn: parent
      width: 460
      height: 900
      color: Commons.Color.popups.background
      Loader {
        id: pageLoader
        x: 16
        y: 16
        width: 428
        active: root.currentRow !== null
        sourceComponent: OmaDroid.DevicePage {
          width: 428
          device: root.currentRow
          actions: fakeActions
          session: fakeSession
          devices: fakeDiscovery.rows
          section: root.frameName.split("-")[1]
        }
      }
    }
  }
  Timer {
    interval: 4000
    running: true
    repeat: true
    onTriggered: {
      if (root.frame >= root.frames.length) {
        console.log("OMADROID_PREVIEW_OK");
        Qt.quit();
        return;
      }
      if (!pageLoader.item) {
        console.error("OMADROID_TEST_FAILED: no row for " + root.currentSerial + " in " + JSON.stringify(fakeDiscovery.rows.map(row => row.serial)));
        Qt.exit(1);
        return;
      }
      var name = root.frameName;
      var click = name.split("-")[2];
      if (click && !root.clicked) {
        var target = finder.findChild(pageLoader.item, click);
        if (!target) {
          console.error("OMADROID_TEST_FAILED: " + name + " has no " + click);
          Qt.exit(1);
          return;
        }
        target.clicked();
        root.clicked = true;
        return;
      }
      if (pageLoader.item.implicitWidth > 428)
        console.error("OMADROID_TEST_FAILED: " + name + " widens the popup to " + pageLoader.item.implicitWidth);
      if (!surface.grabToImage(function (result) {
        if (!result.saveToFile(Quickshell.env("OMADROID_PREVIEW_DIR") + "/" + name.replace(/[^A-Za-z0-9-]/g, "_") + ".png")) {
          console.error("OMADROID_TEST_FAILED: cannot save capture");
          Qt.exit(1);
          return;
        }
        root.frame++;
        root.clicked = false;
      })) {
        console.error("OMADROID_TEST_FAILED: capture failed");
        Qt.exit(1);
      }
    }
  }
}
