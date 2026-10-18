import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Send text overlay: a centered prompt, opened with
// `omarchy-shell shell toggle pym.omadroid` (bind it to a key), that types
// what you enter on a device. The window follows Omarchy's Reminders prompt
// (plugins/reminders/ReminderFlow.qml); the prompt itself is SendTextCard.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false

  /** Called by the shell on every summon; the payload is unused. */
  function open(payloadJson) {
    opened = true;
    card.reset();
  }

  function close() {
    opened = false;
  }

  function dismiss() {
    opened = false;
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "pym.omadroid");
  }

  DiscoveryConsumer {
    id: consumer
    shell: root.shell
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omadroid-send-text"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    SendTextCard {
      id: card
      width: Math.min(Style.space(420), panel.width - Style.gapsOut * 2)
      anchors.centerIn: parent
      consumer: consumer
      onDismissed: root.dismiss()
    }
  }
}
