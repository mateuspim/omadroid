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
          testRoot.check(unavailable ? sharedDiscovery.mdnsError.indexOf("Daemon not running") >= 0 : sharedDiscovery.mdnsError === "", "mDNS failure was not isolated from shared USB results");
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
          console.log("DROIDLINK_SHARED_TEST_OK");
          Qt.quit();
        });
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
