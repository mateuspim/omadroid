import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The unlock PIN editor: a password field with Save and Forget, shown while
// `editing`. Used by the device page's Info section.
ColumnLayout {
  id: root
  required property var powerState
  property bool editing: false
  spacing: Style.space(5)
  visible: editing

  onEditingChanged: {
    secretField.text = "";
    if (editing)
      Qt.callLater(() => secretField.forceActiveFocus());
  }
  // A closed popup shouldn't keep a half-typed PIN around.
  Connections {
    target: root.powerState
    function onPanelOpenChanged() {
      if (!root.powerState.panelOpen)
        root.editing = false;
    }
  }

  function save() {
    if (!root.powerState.saveSecret(secretField.text))
      return;
    secretField.text = "";
    editing = false;
  }

  RowLayout {
    Layout.fillWidth: true
    TextField {
      id: secretField
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      placeholderText: "Device PIN or password"
      password: true
      maximumLength: 64
      inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
      Accessible.name: "Device PIN or password"
      onAccepted: root.save()
      Keys.onEscapePressed: event => {
        root.editing = false;
        event.accepted = true;
      }
    }
    ActionButton {
      text: "Save"
      enabled: secretField.text.length >= 4 && !root.powerState.busy
      onClicked: root.save()
    }
    ActionButton {
      text: "Forget"
      visible: root.powerState.power !== null && root.powerState.power.secret !== "none"
      enabled: !root.powerState.busy
      onClicked: {
        root.powerState.forgetSecret();
        root.editing = false;
      }
    }
  }
  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Kept in your desktop keyring, never in OmaDroid's settings. It is entered once per unlock; a failed try pauses unlocking until you save it again."
    wrapMode: Text.WordWrap
    font.pixelSize: Style.font.bodySmall
    color: Util.alpha(Commons.Color.foreground, 0.7)
  }
}
