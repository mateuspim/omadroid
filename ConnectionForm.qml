import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

ColumnLayout {
  id: root
  required property var actions
  property bool pairing: false
  property bool fixedPairingHost: false
  spacing: Style.space(8)

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
    if (actions.run(pairing ? "pair" : "connect", target, codeField.text))
      codeField.text = "";
  }

  RowLayout {
    Layout.fillWidth: true
    Label {
      text: "Wireless connection"
      font.bold: true
      Layout.fillWidth: true
    }
    ActionButton {
      text: root.pairing ? "Connect instead" : "Pair a device"
      onClicked: root.pairing ? root.showConnect() : root.beginManualPair()
    }
  }
  Label {
    Layout.fillWidth: true
    text: root.pairing ? (root.fixedPairingHost ? "Open “Pair device with pairing code” on Android, then enter only its pairing port and code." : "Use the host, pairing port, and code from “Pair device with pairing code”. The connection port is different.") : "Enter the IP and port shown on Android's Wireless debugging page. Pair first for a new device."
    color: Util.alpha(Color.foreground, 0.7)
    font.pixelSize: Style.font.bodySmall
  }
  TextField {
    id: endpointField
    Layout.fillWidth: true
    visible: !root.pairing
    placeholderText: "Connection address · 192.168.1.42:37001"
    maximumLength: 260
    enabled: !root.actions.busy
    Accessible.name: "Connection address"
    onAccepted: root.submit()
  }
  RowLayout {
    Layout.fillWidth: true
    visible: root.pairing
    Label {
      Layout.fillWidth: true
      visible: root.fixedPairingHost
      text: "Device · " + pairingHostField.text
      wrapMode: Text.WrapAnywhere
      color: Util.alpha(Color.foreground, 0.8)
      Accessible.name: "Pairing device " + pairingHostField.text
    }
    TextField {
      id: pairingHostField
      Layout.fillWidth: true
      visible: !root.fixedPairingHost
      placeholderText: "Host/IP · 192.168.1.42"
      maximumLength: 240
      enabled: !root.actions.busy
      Accessible.name: "Pairing host or IP"
      onAccepted: pairingPortField.forceActiveFocus()
    }
    TextField {
      id: pairingPortField
      Layout.preferredWidth: Style.space(125)
      placeholderText: "Pairing port"
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
      id: codeField
      visible: root.pairing
      Layout.fillWidth: true
      placeholderText: "Six-digit pairing code"
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
      text: root.actions.busy ? "Working…" : root.pairing ? "Pair" : "Connect"
      enabled: !root.actions.busy && (root.pairing ? Model.pairingEndpoint(pairingHostField.text, pairingPortField.text) !== "" && codeField.text.length === 6 : Model.endpoint(endpointField.text) !== "")
      onClicked: root.submit()
    }
  }
}
