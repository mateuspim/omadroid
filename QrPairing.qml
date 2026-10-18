import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Pairing.js" as Pairing

// Pair with a QR code: show a one-time code, wait for Android to announce the
// pairing service named in it, then pair with its password. The password stays
// in memory only while the code is shown and is passed to adb on stdin.
ColumnLayout {
  id: root
  required property var actions
  // Parsed qr-pair.sh output while a code is shown, else null.
  property var code: null
  property string error: ""
  readonly property var rows: actions.discovery ? actions.discovery.rows : []
  readonly property bool discoveryDown: actions.discovery !== null && actions.discovery.mdnsLevel === "error"
  readonly property string announcedEndpoint: code ? Pairing.qrPairingEndpoint(rows, code.service) : ""
  readonly property string qrScript: decodeURIComponent(Qt.resolvedUrl("scripts/qr-pair.sh").toString().replace(/^file:\/\//, ""))
  spacing: Style.space(10)
  // A scanned code's pair command started; AddDevicePage waits for its result.
  signal pairingStarted

  function show() {
    error = "";
    if (!generator.busy)
      generator.start(["bash", qrScript], 5);
  }
  function cancel() {
    code = null;
  }
  // Android announces the service once the code is scanned; pairing waits for
  // any other ADB command to finish first.
  function pairWhenAnnounced() {
    if (!announcedEndpoint || actions.busy)
      return;
    // Read both first: clearing `code` also clears announcedEndpoint.
    var endpoint = announcedEndpoint, password = code.password;
    code = null;
    if (actions.run("pair", endpoint, password))
      pairingStarted();
  }

  // Deferred: clearing `code` inside the change handler of a binding that
  // reads it is a binding loop.
  onAnnouncedEndpointChanged: Qt.callLater(pairWhenAnnounced)
  Connections {
    target: root.actions
    function onBusyChanged() {
      Qt.callLater(root.pairWhenAnnounced);
    }
  }

  HintLabel {
    horizontalAlignment: Text.AlignHCenter
    text: root.code ? "Wireless debugging › Pair device with QR code, then scan" : "Pair a new device by scanning a code"
    detail: "Android 11 or later: Developer options › Wireless debugging ›\nPair device with QR code. The phone must be on the same network."
  }
  // Dark on white with a four-module quiet zone, whatever the theme, so the
  // phone's scanner reads it.
  Rectangle {
    id: qrFrame
    readonly property int quiet: 4
    readonly property int moduleSize: root.code ? Math.max(3, Math.floor(Style.space(220) / (root.code.size + quiet * 2))) : 0
    Layout.alignment: Qt.AlignHCenter
    visible: root.code !== null
    implicitWidth: root.code ? (root.code.size + quiet * 2) * moduleSize : 0
    implicitHeight: implicitWidth
    color: "#ffffff"
    radius: Style.cornerRadius
    Accessible.role: Accessible.Graphic
    Accessible.name: "Wireless debugging pairing QR code"
    Canvas {
      id: qrCanvas
      objectName: "omadroidQrCanvas"
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onPaint: {
        var context = getContext("2d");
        context.reset();
        if (!root.code)
          return;
        var size = root.code.size, unit = qrFrame.moduleSize, offset = qrFrame.quiet * unit;
        context.fillStyle = "#000000";
        for (var i = 0; i < root.code.cells.length; i++) {
          if (root.code.cells[i] === "1")
            context.fillRect(offset + (i % size) * unit, offset + Math.floor(i / size) * unit, unit, unit);
        }
      }
    }
  }
  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    visible: root.code !== null
    text: "Waiting for the scan…"
    color: Commons.Color.accent
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
  }
  ActionButton {
    objectName: "omadroidQrToggle"
    Layout.alignment: Qt.AlignHCenter
    text: root.code ? "Cancel" : generator.busy ? "Making…" : "Show QR code"
    iconText: root.code ? "" : "󰐲"
    enabled: root.code !== null || (!generator.busy && !root.discoveryDown)
    onClicked: root.code ? root.cancel() : root.show()
  }
  HintLabel {
    horizontalAlignment: Text.AlignHCenter
    visible: root.discoveryDown || root.error !== ""
    urgent: true
    text: "⚠ " + (root.error || "Needs wireless discovery (Avahi), which isn't running.")
  }

  onCodeChanged: qrCanvas.requestPaint()
  Command {
    id: generator
    onFinished: (status, output, stderr) => {
      try {
        if (status !== 0)
          throw new Error(Model.commandError(status, "", stderr, "QR code"));
        root.code = Pairing.parseQrPairing(output);
      } catch (e) {
        root.code = null;
        root.error = e.message;
      }
    }
  }
}
