import QtQuick
import "Model.js" as Model

Item {
  id: root
  property string message: ""
  property bool failed: false
  property string action: ""
  property string target: ""
  property var discovery: null
  // Set when a pair succeeded before Avahi reported the device's connect port.
  property string pairedAwaitingConnect: ""
  readonly property bool busy: command.busy
  signal changed

  function run(kind, address, code) {
    if (busy)
      return false;
    try {
      var args = Model.adbCommand(kind, address);
      if (kind === "pair" && !/^\d{6}$/.test(code || ""))
        throw new Error("Enter the six-digit pairing code shown on Android.");
      action = kind;
      target = args[2];
      failed = false;
      message = ({
          connect: "Connecting to ",
          disconnect: "Disconnecting ",
          pair: "Pairing with "
        })[kind] + target + "…";
      return command.start(args, kind === "pair" ? 40 : 25, kind === "pair" ? code + "\n" : "");
    } catch (e) {
      failed = true;
      message = e.message;
      return false;
    }
  }

  // Pairing alone leaves the device out of `adb devices`; finish the job with
  // the connect port Android advertises over mDNS.
  function connectPairedDevice(pairedAddress) {
    var address = Model.connectEndpointAfterPairing(pairedAddress, discovery ? discovery.rows : []);
    if (!address)
      return false;
    pairedAwaitingConnect = "";
    Qt.callLater(() => run("connect", address));
    return true;
  }

  function giveUpPairedConnect() {
    message = "Paired with " + pairedAwaitingConnect + ". Now connect using the connection port on Android's Wireless debugging page.";
    pairedAwaitingConnect = "";
  }

  Command {
    id: command
    onFinished: (code, output, error) => {
      root.failed = !Model.actionSucceeded(root.action, code, output, error);
      root.message = root.failed ? Model.commandError(code, output, error, "ADB " + root.action) : (({ pair: "Paired with ", connect: "Connected to ", disconnect: "Disconnected " })[root.action] + root.target + ".");
      if (root.action === "pair" && !root.failed && !root.connectPairedDevice(root.target)) {
        root.pairedAwaitingConnect = root.target;
        root.message = "Paired with " + root.target + ". Looking for its connection port…";
        if (!root.discovery)
          root.giveUpPairedConnect();
      }
      root.changed();
      if (root.discovery)
        root.discovery.refresh();
    }
  }
  // Retry once the refresh requested above has finished, not an older scan.
  Connections {
    target: root.discovery
    ignoreUnknownSignals: true
    function onBusyChanged() {
      if (!root.pairedAwaitingConnect || root.discovery.busy || root.discovery.refreshPending)
        return;
      if (!root.connectPairedDevice(root.pairedAwaitingConnect))
        root.giveUpPairedConnect();
    }
  }
}
