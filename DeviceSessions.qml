import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "DeviceActions.js" as DeviceActions

// A device's sessions on its page: the Mirror · Audio · Webcam cards, the
// running session's controls (SessionCard) when it runs on this device, one
// card's options when its ⚙ is open, and the last session message.
//
// The option forms always exist, folded or not: the cards summarize them and
// start sessions through them (profile, recording folder, camera, output),
// so their state survives folding and needs no copy here.
//
// A click starts that kind. While any other session runs (another kind, or
// another device) MirrorSession switches; a recording session first asks
// ("Stop recording & switch?") and a second click within 4 s confirms.
//
// Public API
//   serial, session (MirrorSession), device (this device's row), devices
//   (all rows, to name another device's session), panelOpen,
//   optionsKind ("" | "mirror" | "audio" | "webcam": the open ⚙), armed,
//   cards, sessionHere, previewOpen, mirrorOptions, webcamOptions
//   activate(kind)       what a card click does
//   start(kind)          start (or switch to) that kind, no confirm
//   toggleOptions(kind)  open or fold that card's options
//
// Usage:
//   DeviceSessions { serial: row.serial; device: row; session: mirrorSession; devices: rows }
ColumnLayout {
  id: root
  required property string serial
  required property var session
  property var device: null
  property var devices: []
  property bool panelOpen: true
  property string optionsKind: ""
  // The kind whose card asks to confirm a switch away from a recording.
  property string armed: ""
  property alias previewOpen: card.previewOpen
  readonly property alias mirrorOptions: mirrorForm
  readonly property alias webcamOptions: webcamForm
  readonly property bool ready: device !== null && device.status === "device"
  readonly property bool sessionHere: session.busy && session.sessionSerial === serial
  readonly property string sessionKind: session.sessionType === "webcam" ? "webcam" : session.sessionAudioOnly ? "audio" : "mirror"
  readonly property var sessionDevice: devices.find(row => row.serial === session.sessionSerial) || null
  readonly property var cards: DeviceActions.sessionCards({
    serial: serial,
    missingTools: session.missingTools,
    armed: armed,
    forms: {
      profileName: mirrorForm.profileName,
      profile: mirrorForm.profile,
      webcam: webcamForm.webcam,
      cameras: webcamForm.cameras,
      webcamIssue: webcamForm.webcamIssue
    },
    session: {
      busy: session.busy,
      pid: session.sessionPid,
      serial: session.sessionSerial,
      kind: sessionKind,
      stopping: session.stopping,
      recording: session.sessionRecording,
      pendingKind: session.pendingSwitch ? session.pendingSwitch.kind : "",
      pendingSerial: session.pendingSwitch ? session.pendingSwitch.serial : "",
      deviceName: sessionDevice ? sessionDevice.name : ""
    }
  })
  // One launch per DeviceActions session kind.
  readonly property var startHandlers: ({
    mirror: () => mirrorForm.launch(false),
    audio: () => mirrorForm.launch(true),
    webcam: () => webcamForm.launchWebcam()
  })
  spacing: Style.space(8)

  Component.onCompleted: openWantedPreview()
  onPanelOpenChanged: openWantedPreview()
  Connections {
    target: root.session
    function onPreviewWantedChanged() {
      root.openWantedPreview();
    }
    function onSessionPidChanged() {
      root.openWantedPreview();
    }
    // A confirm is about the session that was running; once it ends, the
    // next click starts at once.
    function onBusyChanged() {
      root.disarm();
    }
  }

  // Example: activate("webcam") while mirroring switches to the webcam.
  function activate(kind) {
    var entry = cards.find(c => c.key === kind);
    if (!entry)
      throw new Error("No session card '" + kind + "'; expected one of " + cards.map(c => c.key).join(", "));
    if (entry.action !== "arm")
      disarm();
    if (entry.action === "start")
      start(kind);
    else if (entry.action === "stop")
      session.stop();
    else if (entry.action === "arm")
      arm(kind);
    else if (entry.action === "options")
      optionsKind = kind;
  }
  // The options fold so the started session's controls come first.
  function start(kind) {
    var launch = startHandlers[kind];
    if (!launch)
      throw new Error("No launch for session kind '" + kind + "'; expected one of " + Object.keys(startHandlers).join(", "));
    optionsKind = "";
    launch();
  }
  function arm(kind) {
    armed = kind;
    armExpiry.restart();
  }
  function disarm() {
    armed = "";
    armExpiry.stop();
  }
  function toggleOptions(kind) {
    disarm();
    optionsKind = optionsKind === kind ? "" : kind;
  }
  // A webcam started from this panel shows its preview once it runs here,
  // and only while the popup is open; the wish is then used up.
  function openWantedPreview() {
    if (!session.previewWanted || !panelOpen || session.sessionType !== "webcam")
      return;
    if (session.sessionPid <= 0 || session.sessionSerial !== serial)
      return;
    card.previewOpen = true;
    session.previewWanted = false;
  }

  Timer {
    id: armExpiry
    interval: 4000
    onTriggered: root.armed = ""
  }

  RowLayout {
    objectName: "sessionCards"
    Layout.fillWidth: true
    spacing: Style.space(6)
    Repeater {
      model: root.cards
      delegate: SessionTile {
        required property var modelData
        Layout.fillHeight: true
        entry: modelData
        optionsOpen: root.optionsKind === modelData.key
        onClicked: root.activate(modelData.key)
        onOptionsToggled: root.toggleOptions(modelData.key)
      }
    }
  }
  SessionCard {
    id: card
    Layout.fillWidth: true
    visible: root.sessionHere
    session: root.session
    device: root.device
    panelOpen: root.panelOpen && root.sessionHere
    webcamChanged: webcamForm.webcamChanged
    compact: root.optionsKind !== ""
    onApplyRequested: webcamForm.applyWebcam()
  }
  // Framed, so the open options read as part of the cards above, not of the
  // device controls below.
  Rectangle {
    objectName: "omadroidNextOptions"
    Layout.fillWidth: true
    visible: root.optionsKind !== ""
    implicitHeight: optionsColumn.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: "transparent"
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Util.alpha(Color.foreground, 0.15)
    ColumnLayout {
      id: optionsColumn
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(10)
      }
      spacing: Style.space(6)
      PanelSectionHeader {
        Layout.fillWidth: true
        text: root.optionsKind === "webcam" ? "WEBCAM OPTIONS" : "MIRROR & AUDIO PROFILE"
      }
      MirrorOptions {
        id: mirrorForm
        Layout.fillWidth: true
        visible: root.optionsKind === "mirror" || root.optionsKind === "audio"
        serial: root.serial
        session: root.session
        ready: root.ready
      }
      WebcamOptions {
        id: webcamForm
        Layout.fillWidth: true
        visible: root.optionsKind === "webcam"
        serial: root.serial
        session: root.session
        ready: root.ready
        panelOpen: root.panelOpen
        scanCameras: root.panelOpen && root.optionsKind === "webcam"
      }
    }
  }
  // The running session's card shows its own messages; this line keeps the
  // last one (an error, "Mirroring ended.") once nothing runs here.
  RowLayout {
    objectName: "sessionMessage"
    Layout.fillWidth: true
    visible: !root.sessionHere && root.session.message !== ""
    spacing: Style.space(6)
    Label {
      Layout.fillWidth: true
      // A wrapped label reports its unwrapped width; with Log beside it,
      // that could widen the popup.
      Layout.preferredWidth: 1
      text: (root.session.failed ? "⚠ " : "") + root.session.message
      color: root.session.failed ? Color.urgent : Util.alpha(Color.foreground, 0.7)
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 3
      elide: Text.ElideRight
      font.pixelSize: Style.font.bodySmall
      Accessible.name: text
    }
    ActionButton {
      text: "Log"
      visible: root.session.terminalLaunched
      tooltipText: "Show or hide the terminal of the last session, with scrcpy's output"
      onClicked: root.session.toggleLog()
    }
  }
}
