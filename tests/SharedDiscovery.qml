import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as DroidLink

ShellRoot {
  id: testRoot
  property int completedScans: 0
  property int actionStep: 0

  function check(condition, message) {
    if (!condition) {
      console.error("DROIDLINK_SHARED_TEST_FAILED: " + message);
      Qt.exit(1);
    }
  }

  DroidLink.Discovery {
    id: sharedDiscovery
    intervalSec: 3600

    onBusyChanged: if (!busy && initialized) {
      Qt.callLater(function () {
        testRoot.completedScans++;
        if (testRoot.completedScans === 1) {
          testRoot.check(consumerA.item.discovery === sharedDiscovery && consumerB.item.discovery === sharedDiscovery, "consumers do not share the discovery owner");
          testRoot.check(consumerA.item.discovery.rows === consumerB.item.discovery.rows, "consumers do not observe the same rows");
          refreshMarker.running = true;
        } else if (testRoot.completedScans === 3) {
          testRoot.check(consumerA.item.discovery.readyCount === 2 && consumerB.item.discovery.readyCount === 2, "shared results did not update both consumers");
          var unavailable = Quickshell.env("DROIDLINK_TEST_CASE") === "avahi_unavailable";
          testRoot.check(unavailable ? sharedDiscovery.mdnsLevel === "error" && sharedDiscovery.mdnsDetails.indexOf("Daemon not running") >= 0 : sharedDiscovery.mdnsError === "", "mDNS failure was not isolated from shared USB results");
          consumerA.active = false;
          consumerB.item.refresh();
        } else if (testRoot.completedScans === 4) {
          testRoot.check(!consumerA.item && consumerB.item.discovery.readyCount === 2, "removing one consumer stopped shared discovery");
          actions.run("connect", "phone.local:37001", "");
        }
      });
    }
  }

  Component {
    id: consumerComponent
    DroidLink.DiscoveryConsumer {
      shell: serviceHost
      intervalSec: 3600
    }
  }

  Loader {
    id: consumerA
    sourceComponent: consumerComponent
  }

  Loader {
    id: consumerB
    sourceComponent: consumerComponent
  }

  QtObject {
    id: serviceHost
    function serviceFor(pluginId) {
      testRoot.check(pluginId === "pym.droidlink", "consumer requested the wrong plugin service");
      return sharedDiscovery;
    }
  }

  QtObject {
    id: discoverySpy
    property int refreshCalls: 0
    function refresh() { refreshCalls++; }
  }

  DroidLink.Actions {
    id: actions
    discovery: discoverySpy
    onChanged: {
      if (testRoot.actionStep === 0) {
        testRoot.actionStep = 1;
        Qt.callLater(function () {
          testRoot.check(discoverySpy.refreshCalls === 1, "connect did not request shared discovery");
          actions.run("pair", "phone.local:42000", "123456");
        });
      } else if (testRoot.actionStep === 1) {
        testRoot.actionStep = 2;
        Qt.callLater(function () {
          testRoot.check(discoverySpy.refreshCalls === 2, "pair did not request shared discovery");
          actions.run("disconnect", "phone.local:37001", "");
        });
      } else if (testRoot.actionStep === 2) {
        testRoot.actionStep = 3;
        Qt.callLater(function () {
          testRoot.check(discoverySpy.refreshCalls === 3, "disconnect did not request shared discovery");
          pairActions.run("pair", "192.168.1.5:42000", "123456");
        });
      }
    }
  }

  // Avahi reports the tablet's connect port only on the refresh after pairing,
  // so Actions must wait for that scan and then connect by itself.
  QtObject {
    id: pairingDiscovery
    property var rows: []
    property bool busy: false
    property bool refreshPending: false
    function refresh() {
      busy = true;
      rows = [{ pair: false, service: "_adb-tls-connect._tcp", endpoint: "192.168.1.5:37002" }];
      Qt.callLater(() => busy = false);
    }
  }

  DroidLink.Actions {
    id: pairActions
    discovery: pairingDiscovery
    onChanged: {
      if (action === "pair" && testRoot.actionStep < 4) {
        testRoot.check(!failed && message.indexOf("Looking for its connection port") >= 0, "pair without a known port did not wait for discovery: " + message);
      } else if (action === "connect" && target === "192.168.1.5:37002") {
        testRoot.check(!failed && message === "Connected to 192.168.1.5:37002.", "paired device was not connected: " + message);
        Qt.callLater(() => pairActions.run("pair", "192.168.1.5:42000", "123456"));
        testRoot.actionStep = 4;
      }
    }
  }

  // With the port already known, the connect follows the pair immediately.
  Connections {
    target: pairActions
    function onChanged() {
      if (testRoot.actionStep !== 4 || pairActions.action !== "pair")
        return;
      testRoot.check(pairActions.pairedAwaitingConnect === "", "known connect port was not used immediately");
      testRoot.actionStep = 5;
    }
  }
  Connections {
    target: pairActions
    function onBusyChanged() {
      if (testRoot.actionStep === 5 && !pairActions.busy && pairActions.action === "connect") {
        testRoot.check(!pairActions.failed, "immediate connect after pairing failed: " + pairActions.message);
        console.log("DROIDLINK_SHARED_TEST_OK");
        Qt.quit();
      }
    }
  }

  Process {
    id: refreshMarker
    command: ["touch", Quickshell.env("DROIDLINK_REFRESH_MARKER")]
    onExited: {
      consumerA.item.refresh();
      consumerB.item.refresh();
      testRoot.check(sharedDiscovery.busy, "first consumer refresh did not start discovery");
      testRoot.check(sharedDiscovery.refreshPending, "second consumer refresh was not coalesced");
    }
  }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      testRoot.check(false, "shared discovery test timed out");
    }
  }
}
