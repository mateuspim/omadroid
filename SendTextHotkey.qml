import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Settings row for the Send text overlay's key binding. hotkey.sh keeps it in
// a OmaDroid block of ~/.config/hypr/bindings.lua; nothing is written until
// Install is pressed.
ColumnLayout {
  id: root
  readonly property string hotkeyScript: decodeURIComponent(Qt.resolvedUrl("hotkey.sh").toString().replace(/^file:\/\//, ""))
  // The combination in bindings.lua, "" when none; null until read.
  property var installed: null
  property string message: ""
  property bool failed: false
  spacing: Style.space(4)

  function run(args) {
    if (!hotkeyCommand.start(["bash", hotkeyScript].concat(args), 15))
      return;
    message = "";
    failed = false;
  }

  // `hotkey.sh` prints "installed COMBO" or "none" after every command.
  function finish(code, output, error) {
    var match = /^installed (.+)$/.exec(output.trim());
    if (code === 0) {
      installed = match ? match[1] : "";
      if (match)
        comboField.text = match[1];
      return;
    }
    failed = true;
    message = "⚠ " + (error.trim() || "hotkey.sh exited " + code + ".");
  }

  Component.onCompleted: run(["status"])

  Command {
    id: hotkeyCommand
    onFinished: (code, output, error) => root.finish(code, output, error)
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)
    TextField {
      id: comboField
      objectName: "omadroidHotkeyCombo"
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: "SUPER + ALT + D"
      Accessible.name: "Send text key combination"
      onAccepted: root.run(["set", text])
    }
    ActionButton {
      objectName: "omadroidHotkeyInstall"
      text: root.installed ? "Update" : "Install"
      enabled: !hotkeyCommand.busy && root.installed !== null && comboField.text.trim() !== "" && comboField.text.trim() !== root.installed
      onClicked: root.run(["set", comboField.text])
    }
    ActionButton {
      objectName: "omadroidHotkeyRemove"
      visible: !!root.installed
      text: "Remove"
      enabled: !hotkeyCommand.busy
      onClicked: root.run(["remove"])
    }
  }
  HintLabel {
    objectName: "omadroidHotkeyStatus"
    text: root.message || (root.installed ? "Installed · opens the Send text prompt" : "Opens a prompt for typing on a device")
    urgent: root.failed
    detail: "Kept in a OmaDroid block of ~/.config/hypr/bindings.lua;\nnothing is written until Install."
  }
}
