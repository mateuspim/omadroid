import QtQuick
import "Model.js" as Model
import "Pairing.js" as Pairing

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
  readonly property string wirelessScript: decodeURIComponent(Qt.resolvedUrl("go-wireless.sh").toString().replace(/^file:\/\//, ""))
  signal changed

  // `code` is the six-digit code typed from Android, or a QR code's password.
  function run(kind, address, code) {
    if (busy)
      return false;
    try {
      var args = Model.adbCommand(kind, address);
      if (kind === "pair" && !Pairing.validPairingSecret(code))
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

  /** Move a USB device to wireless ADB through go-wireless.sh, so its cable can
   * be unplugged. Example: actions.goWireless("R5CR123ABC") */
  function goWireless(serial) {
    if (busy)
      return false;
    action = "wireless";
    target = serial;
    failed = false;
    message = "Moving " + serial + " to Wi-Fi…";
    // Up to ~10 s for Wireless debugging to start, then connect retries.
    return command.start(["bash", wirelessScript, serial], 60, "");
  }

  function finishWireless(code, output, error) {
    failed = code !== 0;
    message = failed ? Model.commandError(code, "", error, "Go wireless") : output.trim().split("\n").pop();
  }

  function finishAdb(code, output, error) {
    failed = !Model.actionSucceeded(action, code, output, error);
    message = failed ? Model.commandError(code, output, error, "ADB " + action) : (({ pair: "Paired with ", connect: "Connected to ", disconnect: "Disconnected " })[action] + target + ".");
    if (action === "pair" && !failed && !connectPairedDevice(target)) {
      pairedAwaitingConnect = target;
      message = "Paired with " + target + ". Looking for its connection port…";
      if (!discovery)
        giveUpPairedConnect();
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
      if (root.action === "wireless")
        root.finishWireless(code, output, error);
      else
        root.finishAdb(code, output, error);
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
