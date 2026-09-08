import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

ColumnLayout {
  id: root
  required property var actions
  property bool pairing: false
  spacing: Style.space(8)

  function beginPair(address) {
    pairing = true;
    endpointField.text = address;
    codeField.text = "";
    codeField.forceActiveFocus();
  }
  function clearCode() {
    codeField.text = "";
  }
  function submit() {
    if (actions.run(pairing ? "pair" : "connect", endpointField.text, codeField.text))
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
      onClicked: {
        root.pairing = !root.pairing;
        root.clearCode();
      }
    }
  }
  Label {
    Layout.fillWidth: true
    text: root.pairing ? "Use the address and code from “Pair device with pairing code”. The pairing port differs from the connection port." : "Enter the IP and port shown on Android's Wireless debugging page. Pair first for a new device."
    color: Util.alpha(Color.foreground, 0.7)
    font.pixelSize: Style.font.bodySmall
  }
  TextField {
    id: endpointField
    Layout.fillWidth: true
    placeholderText: root.pairing ? "Pairing address · 192.168.1.42:42000" : "Connection address · 192.168.1.42:37001"
    maximumLength: 260
    enabled: !root.actions.busy
    Accessible.name: root.pairing ? "Pairing address" : "Connection address"
    onAccepted: if (root.pairing)
      codeField.forceActiveFocus()
    else
      root.submit()
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
      enabled: !root.actions.busy && Model.endpoint(endpointField.text) !== "" && (!root.pairing || codeField.text.length === 6)
      onClicked: root.submit()
    }
  }
}
