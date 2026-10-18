import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "plugin" as OmaDroid
import "plugin/DeviceListModel.js" as OmaDroidHome

// Offscreen capture of the home view pieces (PanelHeader, SessionBanner,
// DeviceList) fed by a real Discovery over the smoke fixtures:
//   OMADROID_PREVIEW_DIR=/tmp/out OMADROID_PREVIEW_QML=tests/HomePreview.qml bash tests/smoke.sh
// Writes home.png, status.png and empty.png, checks the list never widens the
// 428 px popup and that a refused mDNS Connect falls back to pairing.
ShellRoot {
  id: root
  property int frame: 0
  property string variant: "home"
  property bool pairFallbackSeen: false
  readonly property var frames: ["home", "status", "empty"]
  readonly property bool ready: discovery.initialized && discovery.rows.some(row => row.source === "mdns")

  OmaDroid.Discovery {
    id: discovery
    Component.onCompleted: {
      holdMdns(root, true);
      refresh();
    }
  }
  OmaDroid.Actions {
    id: actions
    discovery: discovery
  }

  FloatingWindow {
    implicitWidth: 460
    implicitHeight: 720
    color: Color.popups.background
    Rectangle {
      id: surface
      width: 460
      height: Math.max(220, layout.implicitHeight + 32)
      color: Color.popups.background
      ColumnLayout {
        id: layout
        x: 16
        y: 16
        width: 428
        spacing: Style.space(12)
        OmaDroid.PanelHeader {
          Layout.fillWidth: true
          subtitle: OmaDroidHome.homeSubtitle(list.rows)
          showRefresh: true
          busy: root.variant === "status"
          tracking: discovery.tracking
          updatedAt: discovery.updatedAt
          intervalSec: discovery.intervalSec
        }
        OmaDroid.SessionBanner {
          Layout.fillWidth: true
          active: root.variant !== "empty"
          kind: root.variant === "status" ? "webcam" : "mirror"
          deviceName: "Desk phone"
        }
        OmaDroid.DeviceList {
          id: list
          Layout.fillWidth: true
          rows: root.variant === "empty" ? [] : discovery.rows
          actions: actions
          initialized: discovery.initialized
          devicesError: root.variant === "status" ? "adb server version (41) doesn't match this client (39); killing and restarting the server" : ""
          mdnsError: root.variant === "status" ? "a wireless device did not answer" : discovery.mdnsError
          mdnsLevel: root.variant === "status" ? "warning" : discovery.mdnsLevel
          mdnsDetails: discovery.mdnsDetails
          onPairDevice: row => root.pairFallbackSeen = row.endpoint === "192.168.1.66:37009"
        }
        // The empty frame also shows a sub-view header (back, no refresh) and
        // a stopping audio banner, so one run covers every header state.
        OmaDroid.PanelHeader {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(24)
          visible: root.variant === "empty"
          showBack: true
          title: "Desk phone with a name long enough to elide in the header"
          subtitle: "Pixel 6 · Android 16 · USB"
        }
        OmaDroid.SessionBanner {
          Layout.fillWidth: true
          active: root.variant === "empty"
          kind: "audio"
          deviceName: "Desk phone"
          stopping: true
        }
      }
    }
  }

  // Probe the pair fallback once: 192.168.1.66 refuses authentication in mock-adb.
  Timer {
    interval: 200
    running: root.ready && !root.pairFallbackSeen && !actions.busy && root.frame === 0
    repeat: true
    onTriggered: {
      running = false;
      list.runRowAction({ key: "mdns:probe", name: "probe", serial: "adb-PROBE", source: "mdns", pair: false, transport: "Wireless", status: "discovered", endpoint: "192.168.1.66:37009" }, "connect");
    }
  }
  Timer {
    interval: 1500
    running: root.ready && root.pairFallbackSeen
    repeat: true
    onTriggered: {
      if (root.frame === 0)
        actions.message = "";
      root.captureFrame();
    }
  }
  Timer {
    interval: 40000
    running: true
    onTriggered: {
      console.error("OMADROID_TEST_FAILED: home preview timed out (ready " + root.ready + ", pair fallback " + root.pairFallbackSeen + ")");
      Qt.exit(1);
    }
  }

  function captureFrame() {
    if (layout.implicitWidth > 428) {
      console.error("OMADROID_TEST_FAILED: home view widens the popup to " + layout.implicitWidth);
      Qt.exit(1);
      return;
    }
    surface.grabToImage(result => {
      if (!result.saveToFile(Quickshell.env("OMADROID_PREVIEW_DIR") + "/" + root.variant + ".png")) {
        console.error("OMADROID_TEST_FAILED: cannot save " + root.variant);
        Qt.exit(1);
      }
      root.nextFrame();
    });
  }

  function nextFrame() {
    root.frame++;
    if (root.frame >= root.frames.length) {
      console.log("OMADROID_PREVIEW_OK");
      Qt.quit();
      return;
    }
    root.variant = root.frames[root.frame];
    // The probe's failure stays up for the status frame only.
    actions.message = root.variant === "status" ? "ADB connect: failed to authenticate to 192.168.1.66:37009" : "";
  }
}
