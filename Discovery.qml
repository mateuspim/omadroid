import QtQuick
import "Model.js" as Model

Item {
  id: root
  property int intervalSec: 15
  property bool active: true
  property var devices: []
  property var services: []
  property string devicesError: ""
  // mdnsError is the short text shown on the page; mdnsLevel is "", "warning" or "error".
  property string mdnsError: ""
  property string mdnsLevel: ""
  property string mdnsDetails: ""
  // Service name → model from earlier scans, to name a device that stops answering.
  property var knownNames: ({})
  property string updatedAt: ""
  property bool initialized: false
  property bool refreshPending: false
  // mDNS results are only shown in the popup, so Avahi runs while a consumer
  // holds it (an open popup). Standalone hosts can opt into background scans.
  property bool mdnsInBackground: false
  property var mdnsHolders: []
  readonly property bool mdnsWanted: mdnsInBackground || mdnsHolders.length > 0
  readonly property string mdnsScript: decodeURIComponent(Qt.resolvedUrl("discover-mdns.sh").toString().replace(/^file:\/\//, ""))
  readonly property bool busy: usb.busy || mdns.busy
  readonly property var rows: Model.deviceRows(devices, services)
  readonly property int readyCount: devices.filter(row => row.status === "device").length

  function refresh() {
    if (busy) {
      refreshPending = true;
      return;
    }
    refreshPending = false;
    usb.start(["adb", "devices", "-l"], 12);
    if (mdnsWanted)
      mdns.start(["bash", mdnsScript], 12);
  }

  function holdMdns(owner, wanted) {
    var holders = mdnsHolders.filter(holder => holder !== owner);
    if (wanted)
      holders.push(owner);
    mdnsHolders = holders;
  }

  onBusyChanged: if (!busy) {
    initialized = true;
    updatedAt = Qt.formatTime(new Date(), "HH:mm:ss");
    if (refreshPending)
      Qt.callLater(refresh);
  }
  Component.onCompleted: if (active)
    refresh()
  Timer {
    interval: Math.max(5, Math.min(3600, root.intervalSec)) * 1000
    running: root.active
    repeat: true
    onTriggered: root.refresh()
  }
  Command {
    id: usb
    onFinished: (code, output, error) => {
      root.devicesError = code === 0 ? "" : Model.commandError(code, output, error, "ADB discovery");
      root.devices = code === 0 ? Model.parseDevices(output) : [];
    }
  }
  Command {
    id: mdns
    onFinished: (code, output, error) => {
      // The helper can return resolved results even when another query fails.
      var services = Model.parseMdns(output);
      var names = Object.assign({}, root.knownNames);
      services.forEach(row => {
        if (row.model)
          names[row.serial] = row.model;
      });
      root.knownNames = names;
      var status = Model.mdnsStatus(code, error, services, names);
      root.mdnsError = status.text;
      root.mdnsLevel = status.level;
      root.mdnsDetails = status.details;
      root.services = services;
    }
  }
}
