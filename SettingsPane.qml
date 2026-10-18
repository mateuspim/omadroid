import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The popup's Settings view. Every option is saved by the shared discovery
// service in OmaDroid's own omadroid.ini, so all widgets show the same values.
ColumnLayout {
  id: root
  required property var consumer
  readonly property var discovery: consumer.discovery
  readonly property var preferences: discovery.preferences
  spacing: Style.space(8)

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
          { key: "autoConnect", label: "Auto-connect", hint: "Reconnect paired devices over Wi-Fi", detail: "Connects a device that was connected over Wi-Fi before as soon as it\nturns on Wireless debugging, even with this popup closed.\nKeeps wireless discovery running in the background." }
        ]
      },
      {
        title: "When a device connects",
        options: [
          { key: "wakeOnConnect", label: "Wake", hint: "Turn the screen on", detail: "Not when the shell starts." },
          { key: "unlockOnConnect", label: "Unlock", hint: "Enter the saved PIN once", detail: "Save the unlock PIN on the device first." }
        ]
      },
      {
        title: "When mirroring starts",
        options: [
          { key: "wakeOnLaunch", label: "Wake", hint: "Turn the screen on first", detail: "Before scrcpy starts." },
          { key: "unlockOnLaunch", label: "Unlock", hint: "Enter the saved PIN once", detail: "Before scrcpy starts. Save the unlock PIN on the device first." }
        ]
      }
    ]
    delegate: ColumnLayout {
      required property var modelData
      required property int index
      Layout.fillWidth: true
      spacing: Style.space(6)
      PanelSeparator {
        Layout.fillWidth: true
        Layout.bottomMargin: Style.space(4)
        visible: index > 0
      }
      PanelSectionHeader {
        text: modelData.title
      }
      Repeater {
        model: modelData.options
        delegate: SettingToggle {
          required property var modelData
          objectName: "omadroidSetting-" + modelData.key
          label: modelData.label
          description: modelData.hint
          detail: modelData.detail
          checked: root.enabled(modelData.key)
          onClicked: root.toggle(modelData.key)
        }
      }
    }
  }
  SettingsSection {
    title: "Send text hotkey"
  }
  SendTextHotkey {
    objectName: "omadroidHotkey"
    Layout.fillWidth: true
  }
  SettingsSection {
    title: "Advanced"
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)
    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      spacing: Style.space(2)
      Label {
        Layout.fillWidth: true
        text: "Scan interval"
        font.bold: true
      }
      HintLabel {
        text: "Seconds, when adb can't push changes"
        detail: "Fallback scan every 5–3600 s, only used while adb\ncan't report device changes live."
      }
    }
    NumberField {
      objectName: "omadroidScanInterval"
      from: 5
      to: 3600
      // The service clamps too, so a stale or hand-edited value still shows saved.
      value: root.preferences.refreshIntervalSec
      field.Accessible.name: "Fallback scan interval in seconds"
      onModified: seconds => root.consumer.setPreference("refreshIntervalSec", seconds)
    }
  }
  HintLabel {
    Layout.topMargin: Style.space(4)
    text: "Saved in omadroid.ini"
    color: Util.alpha(Commons.Color.foreground, 0.45)
  }

  // Separator + header between the sections that aren't toggle lists.
  component SettingsSection: ColumnLayout {
    property alias title: sectionHeader.text
    Layout.fillWidth: true
    spacing: Style.space(6)
    PanelSeparator {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(4)
      Layout.bottomMargin: Style.space(4)
    }
    PanelSectionHeader {
      id: sectionHeader
    }
  }
}
