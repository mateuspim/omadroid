import QtQuick
import "Model.js" as Model

Item {
  id: root
  property int intervalSec: 15
  property bool active: true
  property var devices: []
  property var services: []
  property string devicesError: ""
  property string mdnsError: ""
  property string updatedAt: ""
  property bool initialized: false
  property bool refreshPending: false
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
    mdns.start(["bash", mdnsScript], 12);
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
      root.mdnsError = code === 0 ? error.trim() : Model.commandError(code, "", error, "mDNS discovery");
      // The helper can return resolved results even when another query fails.
      root.services = Model.parseMdns(output);
    }
  }
}
