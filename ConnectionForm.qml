import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Pair with a pairing code (`pairing`) or connect to an address. The mode is
// switched by AddDevicePage through beginPair / beginManualPair / showConnect.
ColumnLayout {
  id: root
  required property var actions
  property bool pairing: false
  property bool fixedPairingHost: false
  spacing: Style.space(8)
  // A pair or connect from this form started; AddDevicePage waits for its result.
  signal submitted

  function focusPairingInput(hostKnown) {
    Qt.callLater(function() {
      var field = hostKnown ? pairingPortField : pairingHostField;
      field.forceActiveFocus();
      if (hostKnown)
        field.selectAll();
    });
  }
  function beginPair(row, rows, fixHost) {
    var selected = typeof row === "string" ? { endpoint: row, pair: false } : row;
    var prefill = Model.pairingPrefill(selected, rows);
    pairing = true;
    fixedPairingHost = !!fixHost && prefill.host !== "";
    pairingHostField.text = prefill.host;
    pairingPortField.text = prefill.port;
    codeField.text = "";
    focusPairingInput(prefill.host !== "");
  }
  function beginManualPair() {
    beginPair({ endpoint: endpointField.text, pair: false }, [], false);
  }
  function showConnect() {
    pairing = false;
    fixedPairingHost = false;
    clearCode();
    Qt.callLater(function() { endpointField.forceActiveFocus(); });
  }
  function clearCode() {
    codeField.text = "";
  }
  function submit() {
    var target = pairing ? Model.pairingEndpoint(pairingHostField.text, pairingPortField.text) : endpointField.text;
    if (!actions.run(pairing ? "pair" : "connect", target, codeField.text))
      return;
    codeField.text = "";
    submitted();
  }

  HintLabel {
    text: !root.pairing ? "Address and port from Wireless debugging" : root.fixedPairingHost ? "Port and code from “Pair device with pairing code”" : "Wireless debugging › Pair device with pairing code"
    detail: root.pairing ? "Enter the IP address, pairing port and six-digit code that Android\nshows under “Pair device with pairing code”. The pairing port is\nnot the connection port." : "For a device paired with this computer before.\nPair a new device with a QR code or pairing code first."
  }
  RowLayout {
    Layout.fillWidth: true
    visible: root.pairing
    Label {
      Layout.fillWidth: true
      visible: root.fixedPairingHost
      Layout.preferredWidth: 1
      text: "󰄜  " + pairingHostField.text
      wrapMode: Text.WrapAnywhere
      color: Util.alpha(Commons.Color.foreground, 0.8)
      Accessible.name: "Pairing device " + pairingHostField.text
    }
    TextField {
      id: pairingHostField
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      visible: !root.fixedPairingHost
      placeholderText: "Host · 192.168.1.42"
      maximumLength: 240
      enabled: !root.actions.busy
      Accessible.name: "Pairing host or IP"
      onAccepted: pairingPortField.forceActiveFocus()
    }
    TextField {
      id: pairingPortField
      Layout.preferredWidth: Style.space(96)
      placeholderText: "Port"
      maximumLength: 5
      inputMethodHints: Qt.ImhDigitsOnly
      validator: RegularExpressionValidator {
        regularExpression: /[0-9]{0,5}/
      }
      enabled: !root.actions.busy
      Accessible.name: "Pairing port"
      onAccepted: codeField.forceActiveFocus()
    }
  }
  RowLayout {
    Layout.fillWidth: true
    TextField {
      id: endpointField
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      visible: !root.pairing
      placeholderText: "192.168.1.42:37001"
      maximumLength: 260
      enabled: !root.actions.busy
      Accessible.name: "Connection address"
      onAccepted: root.submit()
    }
    TextField {
      id: codeField
      visible: root.pairing
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      placeholderText: "Six-digit code"
      password: true
      maximumLength: 6
      inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
      validator: RegularExpressionValidator {
        regularExpression: /[0-9]{0,6}/
      }
      enabled: !root.actions.busy
      Accessible.name: "Six-digit pairing code"
      onAccepted: root.submit()
    }
    ActionButton {
      objectName: "omadroidConnectionSubmit"
      text: root.actions.busy ? "Working…" : root.pairing ? "Pair" : "Connect"
      enabled: !root.actions.busy && (root.pairing ? Model.pairingEndpoint(pairingHostField.text, pairingPortField.text) !== "" && codeField.text.length === 6 : Model.endpoint(endpointField.text) !== "")
      onClicked: root.submit()
    }
  }
}
