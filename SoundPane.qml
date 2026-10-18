import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "SoundVolume.js" as SoundVolume

// The device page's Sound section: volume keys, mute all and ringer mode,
// per-app volume and the system sound streams of one ready device, through
// device-volume.sh. Android has no volume change events for the shell, so the
// section reads the device every 2 s, and only while it is shown.
ColumnLayout {
  id: root
  // The device whose sound is shown; only this device is read.
  property string serial: ""
  // The section is shown and the popup is open.
  property bool active: false
  readonly property string target: serial
  // Parsed `device-volume.sh status` of `target`; null until read.
  property var volume: null
  readonly property var apps: volume ? SoundVolume.visibleApps(volume.apps) : []
  // The rows' keys (app uids, stream keys). They change only when a row comes
  // or goes, so a new reading moves the sliders instead of rebuilding them;
  // rebuilding destroyed the slider being dragged.
  property var appKeys: []
  property var streamKeys: []
  // The page's Flickable, which the wheel scrolls over a slider.
  property var scrollView: null
  // A failed change stays until the next change; a failed read until a read works.
  property string changeError: ""
  property string readError: ""
  // Changes waiting for the running one, oldest first. A new volume for the
  // same slider replaces its waiting one, so a drag only sends its latest value.
  property var queued: []
  // Bumped per change sent, so a read that started before it is dropped
  // instead of moving the slider back.
  property int changes: 0
  property int readStartedAt: 0
  // The device the running read asked for; `target` can change meanwhile.
  property string readSerial: ""
  readonly property string volumeScript: decodeURIComponent(Qt.resolvedUrl("device-volume.sh").toString().replace(/^file:\/\//, ""))
  spacing: Style.space(10)

  onActiveChanged: active ? refresh() : queued = []
  onVolumeChanged: {
    var apps = root.apps.map(app => app.uid);
    var streams = volume ? volume.streams.map(stream => stream.key) : [];
    if (JSON.stringify(apps) !== JSON.stringify(appKeys))
      appKeys = apps;
    if (JSON.stringify(streams) !== JSON.stringify(streamKeys))
      streamKeys = streams;
  }
  onTargetChanged: {
    volume = null;
    changeError = "";
    readError = "";
    refresh();
  }

  function refresh() {
    if (!active || !target || status.busy)
      return;
    readStartedAt = changes;
    readSerial = target;
    // The first read of a firmware copies its framework (about 53 MB).
    status.start(["bash", volumeScript, "status", target], 120);
  }
  // args: [command, …] without the serial; kind/id/change show the result at once.
  function send(args, kind, id, change) {
    if (kind)
      volume = SoundVolume.withChange(volume, kind, id, change);
    queued = SoundVolume.queueChange(queued, ["bash", volumeScript, args[0], target].concat(args.slice(1)));
    sendQueued();
  }
  function sendQueued() {
    if (!queued.length || change.busy)
      return;
    var next = queued[0];
    queued = queued.slice(1);
    changes += 1;
    changeError = "";
    change.start(next, 15);
  }
  function appRow(uid) {
    return volume ? volume.apps.find(app => app.uid === uid) || null : null;
  }
  function streamRow(key) {
    return volume ? volume.streams.find(stream => stream.key === key) || null : null;
  }
  // A drag reports every pixel; only a changed whole value is sent.
  function setApp(app, value) {
    if (!app || app.volume === value)
      return;
    send(["app", String(app.uid), "set", String(value)], "app", app.uid, { volume: value });
  }
  function toggleApp(app) {
    send(["app", String(app.uid), app.muted ? "unmute" : "mute"], "app", app.uid, { muted: !app.muted });
  }
  // Reads the state before changing it: the button's binding flips with it.
  function toggleMaster() {
    var muted = volume !== null && volume.master === true;
    volume = Object.assign({}, volume, { master: !muted });
    send(["master", muted ? "unmute" : "mute"]);
  }
  function setStream(stream, value) {
    if (!stream || stream.volume === value)
      return;
    send(["stream", stream.key, "set", String(value)], "stream", stream.key, { volume: value });
  }
  function toggleStream(stream) {
    send(["stream", stream.key, stream.muted ? "unmute" : "mute"], "stream", stream.key, { muted: !stream.muted });
  }

  Label {
    Layout.fillWidth: true
    visible: root.target !== "" && root.volume === null && status.busy
    text: "Reading sound settings… The first time on a device takes a few seconds."
    color: Util.alpha(Commons.Color.foreground, 0.7)
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: root.volume !== null
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      ActionButton {
        text: "−"
        tooltipText: "Volume down, like the device's own key"
        Accessible.name: "Volume down"
        onClicked: root.send(["key", "down"])
      }
      ActionButton {
        text: "+"
        tooltipText: "Volume up, like the device's own key"
        Accessible.name: "Volume up"
        onClicked: root.send(["key", "up"])
      }
      ActionButton {
        objectName: "soundMuteAll"
        readonly property bool on: root.volume !== null && root.volume.master === true
        visible: root.volume !== null && root.volume.master !== null
        text: (on ? "✓ " : "○ ") + "Mute all"
        selected: on
        tooltipText: "Silence every sound on the device; app and system volumes are kept"
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: on
        onClicked: root.toggleMaster()
      }
      Item {
        Layout.fillWidth: true
      }
      Repeater {
        model: [
          { key: "normal", label: "Sound" },
          { key: "vibrate", label: "Vibrate" },
          { key: "silent", label: "Silent" }
        ]
        delegate: ActionButton {
          required property var modelData
          objectName: "soundRinger-" + modelData.key
          text: modelData.label
          selected: root.volume !== null && root.volume.ringer === modelData.key
          tooltipText: "Ringer mode"
          onClicked: {
            root.volume = Object.assign({}, root.volume, { ringer: modelData.key });
            root.send(["ringer", modelData.key]);
          }
        }
      }
    }

    PanelSectionHeader {
      Layout.fillWidth: true
      text: "APPS"
    }
    Label {
      Layout.fillWidth: true
      visible: root.apps.length === 0
      text: "No app is playing sound."
      color: Util.alpha(Commons.Color.foreground, 0.7)
    }
    Label {
      Layout.fillWidth: true
      visible: root.volume !== null && root.volume.mode === "appops" && root.apps.length > 0
      text: "This device has no per-app volume, so apps can only be muted."
      font.pixelSize: Style.font.bodySmall
      color: Util.alpha(Commons.Color.foreground, 0.7)
    }
    Repeater {
      model: root.appKeys
      delegate: SoundRow {
        required property var modelData
        readonly property var app: root.appRow(modelData)
        Layout.fillWidth: true
        visible: app !== null
        objectName: "soundApp:" + modelData
        scrollView: root.scrollView
        label: app ? app.label : ""
        detail: app && !app.playing ? "paused" : ""
        volume: !app || app.volume === null ? 100 : app.volume
        muted: app !== null && app.muted === true
        canMute: app !== null && app.muted !== null
        hasSlider: app !== null && app.volume !== null
        onVolumeChosen: (value, final) => root.setApp(app, value)
        onMuteToggled: root.toggleApp(app)
      }
    }

    PanelSectionHeader {
      Layout.fillWidth: true
      text: "SYSTEM SOUNDS"
    }
    Repeater {
      model: root.streamKeys
      delegate: SoundRow {
        required property var modelData
        readonly property var stream: root.streamRow(modelData)
        Layout.fillWidth: true
        visible: stream !== null
        objectName: "soundStream:" + modelData
        scrollView: root.scrollView
        label: stream ? stream.label : ""
        volume: stream ? stream.volume : 0
        minimum: stream ? stream.min : 0
        maximum: stream ? stream.max : 15
        muted: stream !== null && stream.muted
        onVolumeChosen: (value, final) => root.setStream(stream, value)
        onMuteToggled: root.toggleStream(stream)
      }
    }
  }

  Repeater {
    model: [root.changeError, root.readError].filter(Boolean)
    delegate: Label {
      required property string modelData
      Layout.fillWidth: true
      text: "⚠ " + modelData
      wrapMode: Text.WordWrap
      color: Commons.Color.urgent
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.active && root.target !== ""
    onTriggered: root.refresh()
  }
  Command {
    id: status
    onFinished: (code, output, error) => {
      var read = { serial: root.readSerial, changes: root.readStartedAt };
      var current = { serial: root.target, changes: root.changes, changing: change.busy || root.queued.length > 0 };
      if (!SoundVolume.statusReadApplies(read, current)) {
        // The target changed while this read ran; read the new one now
        // instead of waiting for the next tick.
        if (read.serial !== current.serial)
          Qt.callLater(root.refresh);
        return;
      }
      var parsed = code === 0 ? SoundVolume.parseVolumeStatus(output) : null;
      if (parsed)
        root.volume = parsed;
      root.readError = parsed ? "" : code === 0 ? "Unexpected sound status: " + output.trim().slice(0, 200) : Model.commandError(code, output, error, "Reading sound settings");
    }
  }
  Command {
    id: change
    onFinished: (code, output, error) => {
      if (code !== 0)
        root.changeError = Model.commandError(code, output, error, "Changing the volume");
      if (root.queued.length)
        return root.sendQueued();
      root.refresh();
    }
  }
}
