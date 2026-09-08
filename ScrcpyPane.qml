import QtQuick
import QtQuick.Layouts
import QtCore as Core
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

ColumnLayout {
  id: root
  required property var devices
  property string selectedSerial: ""
  property var profile: Model.builtInProfiles()[0]
  property string profileName: "Balanced"
  property string baseProfileName: "Balanced"
  property string message: ""
  property bool failed: false
  property bool stopping: false
  property string sessionSerial: ""
  property string sessionRecording: ""
  property bool sessionAudioOnly: false
  readonly property bool busy: mirror.busy
  readonly property var readyDevices: devices.filter(row => row.status === "device")
  readonly property var customProfiles: Model.savedProfiles(saved.profilesJson)
  readonly property var profiles: Model.builtInProfiles().concat(customProfiles)
  readonly property bool selectedReady: readyDevices.some(row => row.serial === selectedSerial)
  readonly property var deviceOptions: readyDevices.map(row => ({
        value: row.serial,
        label: row.name + " · " + row.transport + " · " + row.serial
      }))
  spacing: Style.space(10)

  Core.Settings {
    id: saved
    location: Util.fileUrl((Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/droidlink.ini")
    property string profilesJson: "[]"
    property string lastProfile: "Balanced"
    property string recordingFolder: Quickshell.env("HOME")
  }

  Component.onCompleted: selectProfile(saved.lastProfile)
  onReadyDevicesChanged: {
    // Preserve a vanished selection so unplugging cannot silently redirect a
    // launch to another phone. Only auto-select before any explicit choice.
    if (!selectedSerial && readyDevices.length)
      selectedSerial = readyDevices[0].serial;
  }

  function chooseDevice(serial) {
    selectedSerial = serial;
  }
  function selectProfile(name) {
    var found = profiles.find(p => p.name === name) || profiles[0];
    profile = Object.assign({}, found);
    profileName = found.name;
    baseProfileName = found.name;
    saved.lastProfile = found.name;
  }
  function changeOption(key, value) {
    var next = Object.assign({}, profile);
    next[key] = value;
    profile = next;
    profileName = "Custom";
  }
  function resetOptions() {
    selectProfile(baseProfileName);
    failed = false;
    message = "Options restored from “" + baseProfileName + "”.";
  }
  function saveProfile(name) {
    name = String(name || nameField.text).trim();
    var candidate = Object.assign({}, profile, {
      name: name
    });
    if (!Model.validProfile(candidate) || name === "Custom" || Model.builtInProfiles().some(p => p.name === name)) {
      failed = true;
      message = "Choose a name of 1–48 characters, different from Custom and the built-in profiles.";
      return;
    }
    var list = customProfiles.filter(p => p.name !== name);
    if (list.length >= 30) {
      failed = true;
      message = "Remove a saved profile first (limit: 30).";
      return;
    }
    list.push(candidate);
    saved.profilesJson = JSON.stringify(list);
    selectProfile(name);
    nameField.text = "";
    failed = false;
    message = "Saved profile “" + name + "”.";
  }
  function removeProfile() {
    saved.profilesJson = JSON.stringify(customProfiles.filter(p => p.name !== profileName));
    selectProfile("Balanced");
  }
  function launch(audioOnly) {
    if (busy)
      return;
    failed = false;
    if (!selectedReady) {
      failed = true;
      message = "Select a device that is Ready before launching.";
      return;
    }
    try {
      var path = profile.record ? Model.recordingPath(folderField.text, selectedSerial, new Date(), Math.random().toString(36).slice(2, 10), audioOnly ? "mka" : "mkv") : "";
      var args = audioOnly ? Model.audioOnlyCommand(selectedSerial, profile, path) : Model.scrcpyCommand(selectedSerial, profile, path);
      sessionSerial = selectedSerial;
      sessionRecording = path;
      sessionAudioOnly = !!audioOnly;
      stopping = false;
      message = "Starting " + (audioOnly ? "audio" : "scrcpy") + " for " + selectedSerial + "…";
      mirror.start(args, 0);
    } catch (e) {
      failed = true;
      message = e.message;
    }
  }

  function stop() {
    if (!busy || stopping)
      return;
    stopping = true;
    mirror.interrupt();
  }

  Command {
    id: mirror
    onFinished: (code, output, error) => {
      root.failed = code !== 0 && !mirror.forceStopped;
      root.message = root.failed ? Model.commandError(code, output, error, "scrcpy") : (mirror.forceStopped ? "Session force-stopped after scrcpy did not exit cleanly." : (root.sessionAudioOnly ? "Audio session ended." : "Mirroring ended.")) + (root.sessionRecording ? " Recording: " + root.sessionRecording : "");
      root.stopping = false;
    }
  }

  Label {
    text: "Mirror with scrcpy"
    font.bold: true
    font.pixelSize: Style.font.title
  }
  Label {
    Layout.fillWidth: true
    visible: readyDevices.length === 0 || (!!selectedSerial && !selectedReady)
    text: readyDevices.length === 0 ? "Connect and authorize a device to start mirroring." : "The selected device is no longer ready. Choose another device or reconnect it."
    color: Util.alpha(Color.foreground, 0.7)
  }
  Dropdown {
    Layout.fillWidth: true
    label: "Device"
    value: root.selectedSerial
    options: root.deviceOptions
    enabled: !root.busy && root.readyDevices.length > 0
    onChanged: value => root.chooseDevice(value)
  }
  Dropdown {
    Layout.fillWidth: true
    label: "Launch profile"
    value: root.profileName
    options: root.profiles.map(p => p.name).concat(root.profileName === "Custom" ? ["Custom"] : [])
    onChanged: value => {
      if (value !== "Custom")
        root.selectProfile(value);
    }
  }
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(10)
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Resolution · max edge"
      value: root.profile.maxSize
      options: [
        {
          value: "0",
          label: "Native"
        },
        "720", "1080", "1440", "1920", "2560"]
      onChanged: value => root.changeOption("maxSize", value)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "FPS limit"
      value: root.profile.fps
      options: [
        {
          value: "0",
          label: "Unlimited"
        },
        "15", "24", "30", "60", "90", "120"]
      onChanged: value => root.changeOption("fps", value)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Video codec"
      value: root.profile.codec
      options: [
        {
          value: "h264",
          label: "H.264"
        },
        {
          value: "h265",
          label: "H.265"
        },
        {
          value: "av1",
          label: "AV1"
        }
      ]
      onChanged: value => root.changeOption("codec", value)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Bitrate · Mbps"
      value: root.profile.bitrate
      options: ["2", "4", "8", "12", "16", "20", "32", "50"]
      onChanged: value => root.changeOption("bitrate", value)
    }
  }
  Label {
    Layout.fillWidth: true
    text: "Resolution limits the longest edge and keeps the aspect ratio. Codec and FPS support depend on the device."
    color: Util.alpha(Color.foreground, 0.7)
    font.pixelSize: Style.font.bodySmall
  }
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.space(10)
    rowSpacing: Style.space(6)
    Repeater {
      model: [
        {
          key: "audio",
          label: "Forward audio"
        },
        {
          key: "record",
          label: "Record session"
        },
        {
          key: "screenOff",
          label: "Device screen off"
        },
        {
          key: "fullscreen",
          label: "Fullscreen"
        }
      ]
      delegate: ActionButton {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        text: (root.profile[modelData.key] ? "✓ " : "○ ") + modelData.label
        selected: root.profile[modelData.key]
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: selected
        onClicked: root.changeOption(modelData.key, !root.profile[modelData.key])
      }
    }
  }
  Label {
    Layout.fillWidth: true
    text: "Audio forwarding requires Android 11+. Audio only plays in the background without a window. Stop it here in DroidLink."
    font.pixelSize: Style.font.bodySmall
    color: Util.alpha(Color.foreground, 0.7)
  }
  TextField {
    id: folderField
    Layout.fillWidth: true
    visible: root.profile.record
    text: saved.recordingFolder
    placeholderText: "Existing recording folder · absolute path"
    Accessible.name: "Recording folder"
    onEditingFinished: saved.recordingFolder = text.trim()
  }
  Label {
    Layout.fillWidth: true
    visible: root.profile.record
    text: "A uniquely named MKV file is created for mirroring; audio-only creates MKA. Stop the session to finish the recording."
    font.pixelSize: Style.font.bodySmall
    color: Util.alpha(Color.foreground, 0.7)
  }
  RowLayout {
    Layout.fillWidth: true
    TextField {
      id: nameField
      Layout.fillWidth: true
      maximumLength: 48
      placeholderText: "Save options as…"
      Accessible.name: "Profile name"
      onAccepted: root.saveProfile()
    }
    ActionButton {
      text: "Save"
      enabled: nameField.text.trim() !== ""
      onClicked: root.saveProfile()
    }
    ActionButton {
      text: "Remove"
      visible: root.customProfiles.some(p => p.name === root.profileName)
      onClicked: root.removeProfile()
    }
    ActionButton {
      text: "Reset"
      enabled: root.profileName === "Custom"
      tooltipText: "Restore options from “" + root.baseProfileName + "” without changing saved profiles or connections"
      onClicked: root.resetOptions()
    }
  }
  RowLayout {
    Layout.fillWidth: true
    ActionButton {
      text: root.busy && !root.sessionAudioOnly ? "Mirroring…" : "Launch scrcpy"
      selected: true
      enabled: root.selectedReady && !root.busy
      onClicked: root.launch(false)
    }
    ActionButton {
      text: root.busy && root.sessionAudioOnly ? "Audio playing…" : "Audio only"
      enabled: root.selectedReady && !root.busy
      onClicked: root.launch(true)
    }
    ActionButton {
      text: root.stopping ? "Stopping…" : root.sessionAudioOnly ? "Stop audio" : "Stop mirroring"
      visible: root.busy
      enabled: !root.stopping
      onClicked: root.stop()
    }
  }
  Label {
    Layout.fillWidth: true
    visible: root.busy
    text: "Session: " + root.sessionSerial + (root.sessionAudioOnly ? " · Audio only" : "") + (root.sessionRecording ? "\nRecording: " + root.sessionRecording : "")
    wrapMode: Text.WrapAnywhere
    color: Color.accent
    font.pixelSize: Style.font.bodySmall
  }
  Label {
    Layout.fillWidth: true
    visible: root.message !== "" && !root.busy
    text: root.message
    color: root.failed ? Color.urgent : Color.accent
    wrapMode: Text.WrapAnywhere
  }
}
