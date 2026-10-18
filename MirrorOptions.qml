import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtCore as Core
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Mirror options for one device: profile, video settings, option chips,
// saved profiles, and Launch / Audio only. Profiles and the recording folder
// are saved in omadroid.ini; messages go to the session's message line.
//
// Public API
//   serial (required), session (required, MirrorSession), ready (the device
//   can launch), profile, profileName, customProfiles, launch(audioOnly),
//   selectProfile(name), changeOption(key, value), saveProfile(name),
//   removeProfile(), resetOptions()
//
// Usage:
//   MirrorOptions { serial: "USB123"; session: mirrorSession; ready: row.status === "device" }
ColumnLayout {
  id: root
  required property string serial
  required property var session
  property bool ready: false
  property var profile: Model.builtInProfiles()[0]
  property string profileName: "Balanced"
  property string baseProfileName: "Balanced"
  // A saved profile name awaiting a second Save, and a pending Remove.
  property string confirmOverwrite: ""
  property bool confirmRemove: false
  readonly property var customProfiles: Model.savedProfiles(saved.profilesJson)
  readonly property var profiles: Model.builtInProfiles().concat(customProfiles)
  readonly property bool canLaunch: ready && !session.missingTools && !session.busy
  spacing: Style.space(6)

  Core.Settings {
    id: saved
    location: Util.fileUrl((Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/omadroid.ini")
    property string profilesJson: "[]"
    property string lastProfile: "Balanced"
    property string recordingFolder: Quickshell.env("HOME")
  }
  Component.onCompleted: selectProfile(saved.lastProfile)
  onProfileNameChanged: if (confirmRemove)
    cancelConfirmations()

  // Example: launch(true) starts windowless audio on `serial`.
  function launch(audioOnly) {
    if (session.busy)
      return;
    if (!ready)
      return session.report("Select a device that is Ready before launching.", true, "mirror");
    session.launchMirror(serial, profile, folderField.text, !!audioOnly);
  }
  function selectProfile(name) {
    var found = profiles.find(p => p.name === name) || profiles[0];
    profile = Object.assign({}, found);
    profileName = found.name;
    baseProfileName = found.name;
    saved.lastProfile = found.name;
  }
  // Example: changeOption("fps", "60") makes the options a Custom profile.
  function changeOption(key, value) {
    var next = Object.assign({}, profile);
    next[key] = value;
    if (key === "screenOff" && value)
      next.keepActive = true;
    profile = next;
    profileName = "Custom";
  }
  function resetOptions() {
    selectProfile(baseProfileName);
    session.report("Options restored from “" + baseProfileName + "”.", false, "mirror");
  }
  function invalidProfileName(name, candidate) {
    return !Model.validProfile(candidate) || name === "Custom" || Model.builtInProfiles().some(p => p.name === name);
  }
  // Example: saveProfile("Desk") saves the shown options; a second call
  // within 5 s replaces an existing "Desk".
  function saveProfile(name) {
    name = String(name || nameField.text).trim();
    var candidate = Object.assign({}, profile, { name: name });
    if (invalidProfileName(name, candidate))
      return session.report("Choose a name of 1–48 characters, different from Custom and the built-in profiles.", true, "mirror");
    if (customProfiles.some(p => p.name === name) && confirmOverwrite !== name)
      return askOverwrite(name);
    confirmOverwrite = "";
    var list = customProfiles.filter(p => p.name !== name);
    if (list.length >= 30)
      return session.report("Remove a saved profile first (limit: 30).", true, "mirror");
    list.push(candidate);
    saved.profilesJson = JSON.stringify(list);
    selectProfile(name);
    nameField.text = "";
    session.report("Saved profile “" + name + "”.", false, "mirror");
  }
  function askOverwrite(name) {
    confirmRemove = false;
    confirmOverwrite = name;
    session.report("“" + name + "” already exists. Press Replace to overwrite it.", false, "mirror");
    confirmExpiry.restart();
  }
  function removeProfile() {
    var name = profileName;
    if (!confirmRemove) {
      confirmOverwrite = "";
      confirmRemove = true;
      session.report("Press Confirm to remove “" + name + "”.", false, "mirror");
      confirmExpiry.restart();
      return;
    }
    confirmRemove = false;
    saved.profilesJson = JSON.stringify(customProfiles.filter(p => p.name !== name));
    selectProfile("Balanced");
    session.report("Removed profile “" + name + "”.", false, "mirror");
  }
  function cancelConfirmations() {
    if (confirmRemove || confirmOverwrite)
      session.report("", false, "mirror");
    confirmRemove = false;
    confirmOverwrite = "";
  }

  Timer {
    id: confirmExpiry
    interval: 5000
    onTriggered: root.cancelConfirmations()
  }

  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    visible: !root.ready
    text: "Connect and authorize this device to mirror it."
    color: Util.alpha(Color.foreground, 0.7)
  }
  // Every cell has the same preferred width, so a long option label can
  // never widen the grid past the popup.
  GridLayout {
    objectName: "omadroidMirrorResolution"
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.space(6)
    rowSpacing: Style.space(4)
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.columnSpan: 2
      label: "Profile"
      value: root.profileName
      options: root.profiles.map(p => p.name).concat(root.profileName === "Custom" ? ["Custom"] : [])
      Accessible.name: "Launch profile"
      onChanged: value => {
        if (value !== "Custom")
          root.selectProfile(value);
      }
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Resolution"
      value: root.profile.maxSize
      options: [{ value: "0", label: "Native" }, { value: "720", label: "720 px edge" }, { value: "1080", label: "1080 px edge" }, { value: "1440", label: "1440 px edge" }, { value: "1920", label: "1080p · 1920 edge" }, { value: "2560", label: "1440p · 2560 edge" }, { value: "3840", label: "4K · 3840 edge" }]
      Accessible.name: "Resolution maximum edge"
      onChanged: value => root.changeOption("maxSize", value)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "FPS limit"
      value: root.profile.fps
      options: [{ value: "0", label: "Unlimited" }, "15", "24", "30", "60", "90", "120"]
      Accessible.name: "FPS limit"
      onChanged: value => root.changeOption("fps", value)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Codec"
      value: root.profile.codec
      options: [{ value: "h264", label: "H.264" }, { value: "h265", label: "H.265" }, { value: "av1", label: "AV1" }]
      Accessible.name: "Video codec"
      onChanged: value => root.changeOption("codec", value)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Bitrate"
      value: root.profile.bitrate
      options: ["2", "4", "8", "12", "16", "20", "32", "50", "60"].map(n => ({ value: n, label: n + " Mbps" }))
      Accessible.name: "Video bitrate in megabits per second"
      onChanged: value => root.changeOption("bitrate", value)
    }
  }
  // Chips wrap to the popup width; the long explanations sit in tooltips.
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(4)
    Repeater {
      model: [
        { key: "audio", label: "Audio", tip: "Forward Android audio; support depends on the Android version" },
        { key: "record", label: "Record", tip: "Record video as MKV or an audio-only session as MKA" },
        { key: "screenOff", label: "Screen off", tip: "Turn the phone display off when the next video session starts" },
        { key: "keepActive", label: "Stay awake", tip: "Prevent Android inactivity sleep during the next video session" },
        { key: "fullscreen", label: "Fullscreen", tip: "Start the next scrcpy video window in fullscreen" }
      ]
      delegate: ActionButton {
        required property var modelData
        readonly property bool optionSelected: modelData.key === "keepActive" ? Model.preventsIdleSleep(root.profile) : root.profile[modelData.key]
        // The selected fill marks an option on; a check mark made five
        // chips too wide for one row.
        text: modelData.label
        horizontalPadding: Style.space(10)
        selected: optionSelected
        tooltipText: modelData.tip
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: optionSelected
        Accessible.name: modelData.label
        onClicked: root.changeOption(modelData.key, !optionSelected)
      }
    }
  }
  TextField {
    id: folderField
    Layout.fillWidth: true
    visible: root.profile.record
    text: saved.recordingFolder
    placeholderText: "Recording folder · absolute path"
    Accessible.name: "Recording folder"
    Controls.ToolTip.text: "A unique MKV is created for video; audio-only creates MKA. Stop the session to finalize it."
    Controls.ToolTip.visible: hovered
    onEditingFinished: saved.recordingFolder = text.trim()
  }
  // Saving only makes sense once the options differ from a profile, and
  // removing only for a saved one; otherwise the row stays out of the way.
  RowLayout {
    Layout.fillWidth: true
    visible: root.profileName === "Custom" || root.customProfiles.some(p => p.name === root.profileName) || nameField.text !== ""
    TextField {
      id: nameField
      Layout.fillWidth: true
      maximumLength: 48
      placeholderText: "Save as profile…"
      Accessible.name: "Profile name"
      onAccepted: root.saveProfile()
      onTextChanged: if (root.confirmOverwrite && text.trim() !== root.confirmOverwrite)
        root.cancelConfirmations()
    }
    ActionButton {
      readonly property bool replacing: root.confirmOverwrite !== "" && root.confirmOverwrite === nameField.text.trim()
      text: replacing ? "Replace" : "Save"
      selected: replacing
      enabled: nameField.text.trim() !== ""
      tooltipText: replacing ? "Overwrite the saved profile with the current options" : "Save the current options as a reusable profile"
      onClicked: root.saveProfile()
    }
    ActionButton {
      text: root.confirmRemove ? "Confirm" : "Remove"
      selected: root.confirmRemove
      visible: root.customProfiles.some(p => p.name === root.profileName)
      tooltipText: root.confirmRemove ? "Remove “" + root.profileName + "” permanently" : "Remove this saved profile"
      onClicked: root.removeProfile()
    }
    ActionButton {
      text: "Reset"
      visible: root.profileName === "Custom"
      tooltipText: "Restore options from “" + root.baseProfileName + "” without changing saved profiles or connections"
      onClicked: root.resetOptions()
    }
  }
  RowLayout {
    objectName: "omadroidMirrorLaunch"
    Layout.fillWidth: true
    visible: !root.session.busy
    ActionButton {
      text: "Launch"
      selected: true
      enabled: root.canLaunch
      tooltipText: "Start video mirroring with these options"
      Accessible.name: "Launch scrcpy"
      onClicked: root.launch(false)
    }
    ActionButton {
      text: "Audio only"
      enabled: root.canLaunch
      tooltipText: "Start windowless audio; stop it here in OmaDroid"
      onClicked: root.launch(true)
    }
    Item {
      Layout.fillWidth: true
    }
    ActionButton {
      text: "Log"
      visible: root.session.terminalLaunched
      tooltipText: "Show or hide the terminal of the last session, with scrcpy's output"
      onClicked: root.session.toggleLog()
    }
  }
}
