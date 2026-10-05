import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as DroidLink

ShellRoot {
  id: testRoot
  property int actionStep: 0

  function check(condition, message) {
    if (!condition) {
      console.error("DROIDLINK_SHARED_TEST_FAILED: " + message);
      Qt.exit(1);
    }
  }

  readonly property bool noTrack: Quickshell.env("DROIDLINK_TEST_CASE") === "no_track"
  property int step: 0
  property var rowsBefore: null

  DroidLink.Discovery {
    id: sharedDiscovery
    intervalSec: 3600
  }

  // Discovery is pushed, not scanned, so the steps wait on its state.
  Timer {
    interval: 50
    running: testRoot.step < 4
    repeat: true
    onTriggered: {
      if (testRoot.step === 0 && sharedDiscovery.initialized && !sharedDiscovery.busy) {
        testRoot.check(consumerA.item.discovery === sharedDiscovery && consumerB.item.discovery === sharedDiscovery, "consumers do not share the discovery owner");
        testRoot.check(consumerA.item.discovery.rows === consumerB.item.discovery.rows, "consumers do not observe the same rows");
        testRoot.check(sharedDiscovery.readyCount === 2, "first device list not read");
        testRoot.check(sharedDiscovery.tracking === !testRoot.noTrack, "track-devices state is wrong: " + sharedDiscovery.tracking);
        testRoot.check(sharedDiscovery.services.length === 0 && sharedDiscovery.mdnsDetails === "", "mDNS ran with no popup open");
        consumerA.item.holdMdns(true);
        consumerB.item.holdMdns(true);
        consumerB.item.holdMdns(false);
        testRoot.check(sharedDiscovery.mdnsHolders.length === 1 && sharedDiscovery.mdnsWanted, "an open popup did not hold mDNS");
        testRoot.check(sharedDiscovery.busy, "holding mDNS did not start the browsers");
        testRoot.step = 1;
      } else if (testRoot.step === 1 && !sharedDiscovery.busy) {
        var unavailable = Quickshell.env("DROIDLINK_TEST_CASE") === "avahi_unavailable";
        testRoot.check(unavailable ? sharedDiscovery.mdnsLevel === "error" && sharedDiscovery.mdnsDetails.indexOf("Daemon not running") >= 0 : sharedDiscovery.mdnsError === "" && sharedDiscovery.services.length === 3, "mDNS failure was not isolated from shared USB results: " + sharedDiscovery.mdnsDetails);
        testRoot.check(sharedDiscovery.readyCount === 2, "mDNS changed the adb results");
        testRoot.rowsBefore = sharedDiscovery.rows;
        testRoot.step = 2;
        refreshMarker.running = true;
      } else if (testRoot.step === 3 && !sharedDiscovery.busy && !sharedDiscovery.refreshPending) {
        testRoot.check(consumerA.item.discovery.readyCount === 2 && consumerB.item.discovery.readyCount === 2, "shared results did not update both consumers");
        testRoot.check(sharedDiscovery.rows === testRoot.rowsBefore, "a refresh that found nothing new rebuilt the rows: " + JSON.stringify(sharedDiscovery.rows));
        consumerA.active = false;
        testRoot.check(!sharedDiscovery.mdnsWanted, "a destroyed consumer kept holding mDNS");
        testRoot.step = 4;
        actions.run("connect", "phone.local:37001", "");
      }
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
      testRoot.step = 3;
    }
  }

  Timer {
    interval: 9000
    running: true
    onTriggered: {
      testRoot.check(false, "shared discovery test timed out");
    }
  }
}
