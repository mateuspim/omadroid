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
  spacing: Style.space(5)

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
  Label {
    Layout.fillWidth: true
    text: "Send text hotkey"
    font.bold: true
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)
    TextField {
      id: comboField
      objectName: "omadroidHotkeyCombo"
      Layout.preferredWidth: Style.space(150)
      text: "SUPER + ALT + D"
      Accessible.name: "Send text key combination"
      onAccepted: root.run(["set", text])
    }
    ActionButton {
      objectName: "omadroidHotkeyInstall"
      text: root.installed ? "Update" : "Install"
      enabled: !hotkeyCommand.busy && root.installed !== null && comboField.text.trim() !== ""
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
  Label {
    objectName: "omadroidHotkeyStatus"
    Layout.fillWidth: true
    text: root.message || (root.installed ? root.installed + " opens the Send text prompt. Saved in ~/.config/hypr/bindings.lua." : "Adds a key binding to ~/.config/hypr/bindings.lua that opens a prompt for typing on a device.")
    wrapMode: Text.WordWrap
    color: root.failed ? Color.foreground : Util.alpha(Color.foreground, 0.7)
    font.pixelSize: Style.font.bodySmall
  }
}
