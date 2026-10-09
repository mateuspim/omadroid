import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The popup's Settings page. Every option is saved by the shared discovery
// service in DroidLink's own droidlink.ini, so all widgets show the same values.
ColumnLayout {
  id: root
  required property var consumer
  readonly property var discovery: consumer.discovery
  readonly property var preferences: discovery.preferences
  spacing: Style.space(10)

  // A key of Preferences, or "autoConnect", which AutoConnect keeps.
  function enabled(key) {
    return key === "autoConnect" ? discovery.autoConnect : preferences[key] === true;
  }
  function toggle(key) {
    if (key === "autoConnect")
      return consumer.setAutoConnect(!discovery.autoConnect);
    consumer.setPreference(key, !enabled(key));
  }

  Repeater {
    model: [
      {
        title: "Wireless",
        options: [
          { key: "autoConnect", label: "Auto-connect paired devices", hint: "Connect a device that was connected over Wi-Fi here before as soon as it turns on Wireless debugging, even with this popup closed. Keeps wireless discovery running in the background." }
        ]
      },
      {
        title: "When a device connects",
        options: [
          { key: "wakeOnConnect", label: "Wake", hint: "Turn the screen on (not when the shell starts)." },
          { key: "unlockOnConnect", label: "Unlock", hint: "Enter the saved unlock PIN once. Save the PIN from the device card first." }
        ]
      },
      {
        title: "When mirroring starts",
        options: [
          { key: "wakeOnLaunch", label: "Wake", hint: "Turn the screen on before scrcpy starts." },
          { key: "unlockOnLaunch", label: "Unlock", hint: "Enter the saved unlock PIN once before scrcpy starts." }
        ]
      }
    ]
    delegate: ColumnLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(5)
      Label {
        Layout.fillWidth: true
        text: modelData.title
        font.bold: true
      }
      Repeater {
        model: modelData.options
        delegate: RowLayout {
          required property var modelData
          readonly property bool isOn: root.enabled(modelData.key)
          Layout.fillWidth: true
          spacing: Style.space(10)
          ActionButton {
            objectName: "droidlinkSetting-" + modelData.key
            Layout.minimumWidth: Style.space(120)
            text: (parent.isOn ? "✓ " : "○ ") + modelData.label
            selected: parent.isOn
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: parent.isOn
            onClicked: root.toggle(modelData.key)
          }
          Label {
            Layout.fillWidth: true
            text: modelData.hint
            wrapMode: Text.WordWrap
            color: Util.alpha(Color.foreground, 0.7)
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
  Label {
    Layout.fillWidth: true
    text: "Device list"
    font.bold: true
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)
    TextField {
      id: intervalField
      Layout.preferredWidth: Style.space(120)
      text: String(root.preferences.refreshIntervalSec)
      maximumLength: 4
      inputMethodHints: Qt.ImhDigitsOnly
      validator: RegularExpressionValidator {
        regularExpression: /[0-9]{0,4}/
      }
      Accessible.name: "Fallback refresh interval in seconds"
      // An out-of-range value is clamped to 5–3600 and shown as saved.
      onEditingFinished: {
        root.consumer.setPreference("refreshIntervalSec", text);
        text = String(root.preferences.refreshIntervalSec);
      }
    }
    Label {
      Layout.fillWidth: true
      text: "Seconds between scans (5–3600), only used while adb can't push device changes."
      wrapMode: Text.WordWrap
      color: Util.alpha(Color.foreground, 0.7)
      font.pixelSize: Style.font.bodySmall
    }
  }
  Label {
    Layout.fillWidth: true
    text: "Saved in DroidLink's droidlink.ini."
    color: Util.alpha(Color.foreground, 0.5)
    font.pixelSize: Style.font.bodySmall
  }
}
