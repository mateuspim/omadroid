import QtQuick
import QtCore as Core
import "AutoConnect.js" as AutoConnect

// Connects devices that were ready over Wi-Fi here before, as soon as they
// announce Wireless debugging. Devices are remembered by their mDNS service
// name, whether or not auto-connect is on, and forgotten when they refuse
// this computer. The switch and the list live in DroidLink's own
// droidlink.ini. Lives in the shared discovery service so two bars don't act twice.
Item {
  id: root
  readonly property bool enabled: remembered.enabled
  // droidlink.ini, from Preferences.
  required property string settingsLocation
  property var devices: []
  property var services: []
  // Endpoints tried since they were announced; never retried while they stay.
  property var tried: ({})
  property string target: ""
  readonly property var known: AutoConnect.parseKeys(remembered.trustedJson)
  signal attempted(string endpoint)

  Core.Settings {
    id: remembered
    location: root.settingsLocation
    category: "autoConnect"
    property bool enabled: false
    property string trustedJson: "[]"
  }

  onDevicesChanged: Qt.callLater(update)
  onServicesChanged: Qt.callLater(update)
  onEnabledChanged: Qt.callLater(update)

  /** Turn auto-connect on or off; remembered across restarts.
   * Example: autoConnect.setEnabled(true) */
  function setEnabled(on) {
    remembered.enabled = !!on;
  }
  function update() {
    remember(AutoConnect.trustedKeys(devices, services));
    tried = AutoConnect.stillAnnounced(tried, services);
    if (enabled && !command.busy)
      connectNext();
  }
  function remember(keys) {
    var merged = AutoConnect.rememberKeys(known, keys);
    if (merged.length !== known.length)
      remembered.trustedJson = JSON.stringify(merged);
  }
  function forget(key) {
    if (known.indexOf(key) >= 0)
      remembered.trustedJson = JSON.stringify(known.filter(other => other !== key));
  }
  function connectNext() {
    var targets = AutoConnect.autoConnectTargets(devices, services, known, tried);
    if (!targets.length)
      return;
    target = targets[0];
    var marked = Object.assign({}, tried);
    marked[target] = true;
    tried = marked;
    command.start(["adb", "connect", target], 15);
    attempted(target);
  }

  Command {
    id: command
    // A device that no longer trusts this computer (unpaired on Android) is
    // forgotten; a network failure is left for the next announcement.
    onFinished: (code, output, error) => {
      if (AutoConnect.refusedTrust(output + "\n" + error))
        root.forget(AutoConnect.keyAt(root.services, root.target));
      Qt.callLater(root.update);
    }
  }
}
