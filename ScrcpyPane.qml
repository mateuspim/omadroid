import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
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
  property int sessionPid: 0
  // Supplied by the panel, which runs `session.sh check` on open.
  property string missingTools: ""
  property bool panelOpen: true
  property bool optionsExpanded: false
  readonly property bool busy: sessionPid > 0 || launcher.busy
  readonly property string sessionScript: decodeURIComponent(Qt.resolvedUrl("session.sh").toString().replace(/^file:\/\//, ""))
  readonly property var readyDevices: devices.filter(row => row.status === "device")
  readonly property var customProfiles: Model.savedProfiles(saved.profilesJson)
  readonly property var profiles: Model.builtInProfiles().concat(customProfiles)
  readonly property bool selectedReady: readyDevices.some(row => row.serial === selectedSerial)
  readonly property var deviceOptions: readyDevices.map(row => ({
        value: row.serial,
        label: row.name + " · " + row.transport + " · " + row.serial
      }))
  spacing: Style.space(6)

  Core.Settings {
    id: saved
    location: Util.fileUrl((Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/droidlink.ini")
    property string profilesJson: "[]"
    property string lastProfile: "Balanced"
    property string recordingFolder: Quickshell.env("HOME")
  }

  Component.onCompleted: {
    selectProfile(saved.lastProfile);
    refreshSession();
  }
  onPanelOpenChanged: if (panelOpen)
    refreshSession()
  // Each session starts with its options folded so the session controls fit.
  onBusyChanged: if (busy)
    optionsExpanded = false
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
    if (key === "screenOff" && value)
      next.keepActive = true;
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
    if (missingTools) {
      failed = true;
      message = "Install " + missingTools + " before launching scrcpy.";
      return;
    }
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
      launcher.start(["bash", sessionScript, "launch", selectedSerial, audioOnly ? "1" : "0", path, "--"].concat(args), 6);
    } catch (e) {
      failed = true;
      message = e.message;
    }
  }

  function stop() {
    if (!busy || stopping)
      return;
    stopping = true;
    // Up to 4 s for a clean exit plus 2 s after SIGKILL.
    stopper.start(["bash", sessionScript, "stop"], 10);
  }

  function refreshSession() {
    if (!status.busy)
      status.start(["bash", sessionScript, "status"], 3);
  }
  // A status poll also ends a finished session and releases its owned
  // rotation lock, so keep a slow poll while a session runs behind a closed
  // popup. Closed and idle, nothing polls; opening the popup re-reads state.
  Timer {
    interval: root.panelOpen ? 1000 : 5000
    running: root.panelOpen || root.busy
    repeat: true
    onTriggered: root.refreshSession()
  }
  Command {
    id: status
    onFinished: (code, output, error) => {
      var lines = output.trim().split("\n");
      var wasActive = root.sessionPid > 0;
      if (code === 0 && lines[0] === "active" && lines.length >= 5) {
        root.sessionSerial = lines[1];
        root.sessionAudioOnly = lines[2] === "1";
        root.sessionRecording = lines[3];
        root.sessionPid = Number(lines[4]) || 0;
        // The card header already says the session is running.
        if (root.message.indexOf("Session started") === 0)
          root.message = "";
      } else if (code === 0) {
        root.sessionPid = 0;
        if (wasActive && !root.stopping && root.message.indexOf("Session stopped") !== 0 && root.message.indexOf("Session force-stopped") !== 0) {
          root.failed = false;
          root.message = (root.sessionAudioOnly ? "Audio session ended." : "Mirroring ended.") + (root.sessionRecording ? " Recording: " + root.sessionRecording : "");
        } else if (root.message.indexOf("Session started") === 0) {
          root.message = "scrcpy exited. See the DroidLink terminal for output." + (root.sessionRecording ? " Recording: " + root.sessionRecording : "");
        }
      } else {
        root.failed = true;
        root.message = Model.commandError(code, output, error, "Session status");
      }
    }
  }
  Command {
    id: launcher
    onFinished: (code, output, error) => {
      root.failed = code !== 0;
      root.message = root.failed ? Model.commandError(code, output, error, "scrcpy launch") : output.trim();
      root.refreshSession();
    }
  }
  Command {
    id: stopper
    onFinished: (code, output, error) => {
      root.failed = code !== 0;
      root.message = root.failed ? Model.commandError(code, output, error, "scrcpy stop") : output.trim();
      root.stopping = false;
      root.refreshSession();
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Label {
      Layout.fillWidth: true
      text: "Mirror with scrcpy"
      font.bold: true
      font.pixelSize: Style.font.title
    }
    Label {
      visible: root.busy
      text: root.stopping ? "Stopping…" : "● Active"
      color: Color.accent
      Accessible.name: root.stopping ? "Mirroring session stopping" : "Mirroring session active"
    }
  }
  // While a session runs, its controls come first; the options below only
  // affect the next launch, so they fold away until asked for.
  Rectangle {
    objectName: "droidlinkSessionCard"
    Layout.fillWidth: true
    visible: root.busy
    implicitHeight: sessionCardContent.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.06)
    border.color: Util.alpha(Color.accent, 0.4)
    ColumnLayout {
      id: sessionCardContent
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(12)
      }
      spacing: Style.space(6)
      RowLayout {
        Layout.fillWidth: true
        Label {
          Layout.fillWidth: true
          text: (root.sessionPid > 0 ? (root.sessionAudioOnly ? "Audio only" : "Mirroring") : "Starting") + (root.sessionSerial ? " · " + root.sessionSerial : "")
          font.bold: true
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 2
          elide: Text.ElideRight
          Accessible.name: text
        }
        ActionButton {
          text: root.stopping ? "Stopping…" : root.sessionAudioOnly ? "Stop audio" : "Stop mirroring"
          selected: true
          enabled: root.sessionPid > 0 && !root.stopping
          tooltipText: "Request a clean scrcpy shutdown so recordings can finalize"
          onClicked: root.stop()
        }
      }
      Label {
        Layout.fillWidth: true
        visible: root.sessionRecording !== ""
        text: "Recording: " + root.sessionRecording
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        color: Util.alpha(Color.foreground, 0.7)
        font.pixelSize: Style.font.bodySmall
        Accessible.name: text
      }
      Label {
        Layout.fillWidth: true
        visible: root.message !== ""
        text: (root.failed ? "⚠ " : "") + root.message
        color: root.failed ? Color.urgent : Color.accent
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 3
        elide: Text.ElideRight
        font.pixelSize: Style.font.bodySmall
        Accessible.name: text
      }
      ScreenPowerControls {
        Layout.fillWidth: true
        visible: !root.sessionAudioOnly
        sessionActive: root.busy && !root.stopping && !root.sessionAudioOnly
        sessionPid: root.sessionPid
      }
      ScreenRotationControls {
        Layout.fillWidth: true
        visible: !root.sessionAudioOnly
        sessionActive: root.busy && !root.stopping && !root.sessionAudioOnly
        sessionPid: root.sessionPid
        deviceSerial: root.sessionSerial
        sessionScript: root.sessionScript
      }
    }
  }
  ActionButton {
    Layout.fillWidth: true
    visible: root.busy
    text: (root.optionsExpanded ? "▾ " : "▸ ") + "Next session options"
    tooltipText: "Options apply to the next launch, not the running session"
    Accessible.role: Accessible.Button
    Accessible.checkable: true
    Accessible.checked: root.optionsExpanded
    Accessible.name: "Next session options"
    onClicked: root.optionsExpanded = !root.optionsExpanded
  }
  ColumnLayout {
    objectName: "droidlinkNextOptions"
    Layout.fillWidth: true
    visible: !root.busy || root.optionsExpanded
    spacing: root.spacing
    Label {
      Layout.fillWidth: true
      visible: readyDevices.length === 0 || (!!selectedSerial && !selectedReady)
      text: readyDevices.length === 0 ? "Connect and authorize a device to start mirroring." : "The selected device is no longer ready. Choose another device or reconnect it."
      color: Util.alpha(Color.foreground, 0.7)
    }
    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.space(8)
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Device"
        value: root.selectedSerial
        options: root.deviceOptions
        enabled: !root.busy && root.readyDevices.length > 0
        Accessible.name: "Mirror device"
        onChanged: value => root.chooseDevice(value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Profile"
        value: root.profileName
        options: root.profiles.map(p => p.name).concat(root.profileName === "Custom" ? ["Custom"] : [])
        Accessible.name: "Launch profile"
        onChanged: value => {
          if (value !== "Custom")
            root.selectProfile(value);
        }
      }
    }
    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(4)
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Resolution"
        value: root.profile.maxSize
        options: [
          {
            value: "0",
            label: "Native"
          },
          { value: "720", label: "720 px edge" },
          { value: "1080", label: "1080 px edge" },
          { value: "1440", label: "1440 px edge" },
          { value: "1920", label: "1080p · 1920 edge" },
          { value: "2560", label: "1440p · 2560 edge" },
          { value: "3840", label: "4K · 3840 edge" }]
        Accessible.name: "Resolution maximum edge"
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
        Accessible.name: "FPS limit"
        onChanged: value => root.changeOption("fps", value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Codec"
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
        Accessible.name: "Video codec"
        onChanged: value => root.changeOption("codec", value)
      }
      Dropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: "Bitrate"
        value: root.profile.bitrate
        options: ["2", "4", "8", "12", "16", "20", "32", "50", "60"]
        Accessible.name: "Video bitrate in megabits per second"
        onChanged: value => root.changeOption("bitrate", value)
      }
    }
    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(4)
      Repeater {
        model: [
          {
            key: "audio",
            label: "Audio",
            tip: "Forward Android audio; support depends on the Android version"
          },
          {
            key: "record",
            label: "Recording",
            tip: "Record video as MKV or an audio-only session as MKA"
          },
          {
            key: "screenOff",
            label: "Device screen off",
            tip: "Turn the phone display off when the next video session starts"
          },
          {
            key: "keepActive",
            label: "Prevent idle sleep",
            tip: "Prevent Android inactivity sleep during the next video session"
          },
          {
            key: "fullscreen",
            label: "Fullscreen",
            tip: "Start the next scrcpy video window in fullscreen"
          }
        ]
        delegate: ActionButton {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          readonly property bool optionSelected: modelData.key === "keepActive" ? Model.preventsIdleSleep(root.profile) : root.profile[modelData.key]
          text: (optionSelected ? "✓ " : "○ ") + modelData.label
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
      placeholderText: "Existing recording folder · absolute path"
      Accessible.name: "Recording folder"
      Controls.ToolTip.text: "A unique MKV is created for video; audio-only creates MKA. Stop the session to finalize it."
      Controls.ToolTip.visible: hovered
      onEditingFinished: saved.recordingFolder = text.trim()
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
        tooltipText: "Save the current options as a reusable profile"
        onClicked: root.saveProfile()
      }
      ActionButton {
        text: "Remove"
        visible: root.customProfiles.some(p => p.name === root.profileName)
        tooltipText: "Remove this saved profile"
        onClicked: root.removeProfile()
      }
      ActionButton {
        text: "Reset"
        enabled: root.profileName === "Custom"
        tooltipText: "Restore options from “" + root.baseProfileName + "” without changing saved profiles or connections"
        onClicked: root.resetOptions()
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    visible: !root.busy
    ActionButton {
      text: "Launch scrcpy"
      selected: true
      enabled: root.selectedReady && !root.missingTools
      tooltipText: "Start video mirroring with the selected options"
      onClicked: root.launch(false)
    }
    ActionButton {
      text: "Audio only"
      enabled: root.selectedReady && !root.missingTools
      tooltipText: "Start windowless audio; stop it here in DroidLink"
      onClicked: root.launch(true)
    }
  }
  Label {
    Layout.fillWidth: true
    visible: root.message !== "" && !root.busy
    text: (root.failed ? "⚠ " : "") + root.message
    color: root.failed ? Color.urgent : Color.accent
    wrapMode: Text.WrapAnywhere
    maximumLineCount: 3
    elide: Text.ElideRight
    Accessible.name: text
  }
}
