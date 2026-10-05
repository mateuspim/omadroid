import QtQuick

// Per-widget adapter for the process-wide discovery service. It owns no
// commands or timers; every consumer forwards to the same shell-owned object.
Item {
  id: root

  property var shell: null
  property string pluginId: "pym.droidlink"
  property int intervalSec: 15
  property bool mdnsWanted: false
  readonly property var sharedDiscovery: shell && typeof shell.serviceFor === "function" ? shell.serviceFor(pluginId) : null
  readonly property var discovery: sharedDiscovery || unavailableDiscovery

  function refresh() {
    if (sharedDiscovery)
      sharedDiscovery.refresh();
  }

  // Call before refresh() so the scan that follows includes mDNS.
  function holdMdns(wanted) {
    mdnsWanted = wanted;
    if (sharedDiscovery)
      sharedDiscovery.holdMdns(root, wanted);
  }

  function configure() {
    if (sharedDiscovery) {
      sharedDiscovery.intervalSec = intervalSec;
      sharedDiscovery.holdMdns(root, mdnsWanted);
    }
  }

  onSharedDiscoveryChanged: configure()
  onIntervalSecChanged: configure()
  Component.onCompleted: configure()
  Component.onDestruction: if (sharedDiscovery)
    sharedDiscovery.holdMdns(root, false)

  QtObject {
    id: unavailableDiscovery
    readonly property int intervalSec: 15
    readonly property var devices: []
    readonly property var services: []
    readonly property string devicesError: ""
    readonly property string mdnsError: ""
    readonly property string mdnsLevel: ""
    readonly property string mdnsDetails: ""
    readonly property string updatedAt: ""
    readonly property bool initialized: false
    readonly property bool refreshPending: false
    readonly property bool busy: false
    readonly property bool tracking: false
    readonly property var rows: []
    readonly property int readyCount: 0
  }
}
