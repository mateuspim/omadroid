import QtQuick
import "Model.js" as Model

Item {
  id: root
  property string message: ""
  property bool failed: false
  property string action: ""
  property string target: ""
  property var discovery: null
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

  Command {
    id: command
    onFinished: (code, output, error) => {
      root.failed = !Model.actionSucceeded(root.action, code, output, error);
      root.message = root.failed ? Model.commandError(code, output, error, "ADB " + root.action) : root.action === "pair" ? "Paired with " + root.target + ". Now connect using the connection port on Android's Wireless debugging page." : (root.action === "connect" ? "Connected to " : "Disconnected ") + root.target + ".";
      root.changed();
      if (root.discovery)
        root.discovery.refresh();
    }
  }
}
