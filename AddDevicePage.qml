import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The "Add device" view: one switcher for the three ways to reach a wireless
// device — scan a QR code, type a pairing code, or connect to a known address.
//
// For the panel:
//   beginPair(row, rows, auto)  open "Pairing code" prefilled for a discovery
//                               row or "host:port" (see ConnectionForm.beginPair)
//   clearCode()                 forget a typed pairing code (popup closing)
//   cancel()                    stop showing the QR code and stop waiting for a
//                               result (page left or popup closed)
//   done()                      a pair or connect started here ended with the
//                               device connected; the panel can show the list
// Example: AddDevicePage { actions: actions; onDone: root.view = "home" }
ColumnLayout {
  id: root
  required property var actions
  // "qr", "code" or "address".
  property string mode: "qr"
  // Off when the host already shows Actions' progress and result.
  property bool showStatus: true
  // From a pair or connect started on this page until its outcome is known.
  property bool awaitingResult: false
  signal done
  spacing: Style.space(12)

  function beginPair(row, rows, auto) {
    setMode("code");
    connectionForm.beginPair(row, rows, auto);
  }
  function clearCode() {
    connectionForm.clearCode();
  }
  function cancel() {
    qrPairing.cancel();
    awaitingResult = false;
  }
  function setMode(next) {
    if (next === mode)
      return;
    mode = next;
    if (next !== "qr")
      qrPairing.cancel();
    if (next === "code")
      connectionForm.beginManualPair();
    else if (next === "address")
      connectionForm.showConnect();
  }

  // A successful pair is followed by Actions' own connect, so only a
  // connect (or a failure) ends the wait.
  function settle() {
    if (!awaitingResult || (!actions.failed && actions.action === "pair"))
      return;
    awaitingResult = false;
    if (!actions.failed && actions.action === "connect")
      done();
  }
  // Paired, but Avahi never reported the connect port: Actions asks for the
  // address, so open that form.
  function settleWithoutConnectPort() {
    if (!awaitingResult || actions.busy || actions.pairedAwaitingConnect !== "" || actions.action !== "pair")
      return;
    awaitingResult = false;
    setMode("address");
  }

  Connections {
    target: root.actions
    function onChanged() {
      root.settle();
    }
    function onPairedAwaitingConnectChanged() {
      // Deferred past Actions' own Qt.callLater connect, which sets busy.
      Qt.callLater(root.settleWithoutConnectPort);
    }
  }

  ButtonGroup {
    objectName: "omadroidAddMode"
    Layout.alignment: Qt.AlignHCenter
    value: root.mode
    options: [
      { value: "qr", label: "QR code", tooltip: "Android 11 or later" },
      { value: "code", label: "Pairing code", tooltip: "Type the code Android shows" },
      { value: "address", label: "Address", tooltip: "A device paired before" }
    ]
    onChanged: value => root.setMode(value)
  }
  QrPairing {
    id: qrPairing
    objectName: "omadroidQrPairing"
    Layout.fillWidth: true
    visible: root.mode === "qr"
    actions: root.actions
    onPairingStarted: root.awaitingResult = true
  }
  ConnectionForm {
    id: connectionForm
    objectName: "omadroidConnectionForm"
    Layout.fillWidth: true
    visible: root.mode !== "qr"
    actions: root.actions
    onSubmitted: root.awaitingResult = true
  }
  HintLabel {
    objectName: "omadroidAddStatus"
    visible: root.showStatus && root.actions.message !== ""
    text: (root.actions.failed ? "⚠ " : "") + root.actions.message
    urgent: root.actions.failed
    color: root.actions.failed ? Color.urgent : Color.accent
    Accessible.role: Accessible.StaticText
  }
}
