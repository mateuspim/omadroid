import QtQuick

// Per-widget adapter for the process-wide discovery service. It owns no
// commands or timers; every consumer forwards to the same shell-owned object.
Item {
  id: root

  property var shell: null
  property string pluginId: "pym.droidlink"
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

  // Options are saved by the service in droidlink.ini, so every widget shows
  // the same state and the service acts on connects once.
  function setAutoConnect(on) {
    if (sharedDiscovery)
      sharedDiscovery.setAutoConnect(on);
  }
  function setPreference(name, value) {
    if (sharedDiscovery)
      sharedDiscovery.setPreference(name, value);
  }

  function attach() {
    if (sharedDiscovery)
      sharedDiscovery.holdMdns(root, mdnsWanted);
  }

  onSharedDiscoveryChanged: attach()
  Component.onCompleted: attach()
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
    readonly property bool autoConnect: false
    readonly property var preferences: QtObject {
      readonly property int refreshIntervalSec: 15
      readonly property bool wakeOnLaunch: true
      readonly property bool unlockOnLaunch: false
      readonly property bool wakeOnConnect: false
      readonly property bool unlockOnConnect: false
      readonly property string lastTextTarget: ""
    }
  }
}
