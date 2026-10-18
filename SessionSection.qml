import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The frame shared by the Mirror and Webcam sections of a device page. Its
// default content is the options form (MirrorOptions or WebcamOptions).
//   - A session of this kind runs on this device: the SessionCard comes
//     first and the options fold under "Next session options".
//   - Any other session runs: a one-line notice with Stop, then the options.
//   - Nothing runs: the options, then the last message.
//
// Public API
//   serial, session (MirrorSession), device (this device's row), devices
//   (all rows, to name another device's session), panelOpen, kind
//   ("mirror" | "webcam"), optionsExpanded, previewOpen, webcamChanged,
//   sessionHere, sessionElsewhere, optionsTop
//   signal applyRequested()            the card's Apply was pressed
//   signal showSessionRequested(kind)  the notice was clicked
//
// Usage: see MirrorSection.qml and WebcamSection.qml.
ColumnLayout {
  id: root
  required property string serial
  required property var session
  property var device: null
  property var devices: []
  property bool panelOpen: true
  property string kind: "mirror"
  property bool optionsExpanded: false
  property bool webcamChanged: false
  property alias previewOpen: card.previewOpen
  default property alias optionsContent: optionsColumn.data
  signal applyRequested
  signal showSessionRequested(string kind)

  readonly property bool kindMatches: kind === "webcam" ? session.sessionType === "webcam" : session.sessionType !== "webcam"
  readonly property bool sessionHere: session.busy && kindMatches && session.sessionSerial === serial
  readonly property bool sessionElsewhere: session.busy && !sessionHere
  readonly property string sessionKind: session.sessionType === "webcam" ? "webcam" : "mirror"
  readonly property var sessionDevice: devices.find(row => row.serial === session.sessionSerial) || null
  // Where the folded options start, so the panel can scroll them into view.
  readonly property real optionsTop: nextOptionsToggle.y
  spacing: Style.space(6)

  // Each session starts with its options folded so the session controls fit.
  Connections {
    target: root.session
    function onBusyChanged() {
      if (root.session.busy)
        root.optionsExpanded = false;
    }
  }

  RowLayout {
    objectName: "omadroidOtherSession"
    Layout.fillWidth: true
    visible: root.sessionElsewhere
    spacing: Style.space(6)
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: "● " + root.session.sessionTitle + " · " + (root.sessionDevice ? root.sessionDevice.name : root.session.sessionSerial)
      color: Color.accent
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
      Accessible.name: text + ". End it before starting " + (root.kind === "webcam" ? "the webcam." : "mirroring.")
      TapHandler {
        onTapped: root.showSessionRequested(root.sessionKind)
      }
      HoverHandler {
        cursorShape: Qt.PointingHandCursor
      }
    }
    ActionButton {
      text: root.session.stopping ? "Stopping…" : "Stop"
      enabled: root.session.sessionPid > 0 && !root.session.stopping
      tooltipText: root.session.stopLabel + " · one session runs at a time"
      Accessible.name: root.session.stopLabel
      onClicked: root.session.stop()
    }
  }
  // While a session runs, its controls come first; the options below only
  // affect the next launch, so they fold away until asked for.
  SessionCard {
    id: card
    Layout.fillWidth: true
    visible: root.sessionHere
    session: root.session
    device: root.device
    panelOpen: root.panelOpen && root.sessionHere
    webcamChanged: root.webcamChanged
    compact: root.optionsExpanded
    onApplyRequested: root.applyRequested()
  }
  ActionButton {
    id: nextOptionsToggle
    Layout.fillWidth: true
    visible: root.sessionHere
    text: (root.optionsExpanded ? "▾ " : "▸ ") + "Next session options"
    tooltipText: "Options apply to the next launch, not the running session"
    Accessible.role: Accessible.Button
    Accessible.checkable: true
    Accessible.checked: root.optionsExpanded
    Accessible.name: "Next session options"
    onClicked: root.optionsExpanded = !root.optionsExpanded
  }
  ColumnLayout {
    id: optionsColumn
    objectName: "omadroidNextOptions"
    Layout.fillWidth: true
    visible: !root.sessionHere || root.optionsExpanded
    spacing: root.spacing
  }
  Label {
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    visible: root.session.message !== "" && !root.session.busy
    text: (root.session.failed ? "⚠ " : "") + root.session.message
    color: root.session.failed ? Color.urgent : Color.accent
    wrapMode: Text.WrapAnywhere
    maximumLineCount: 3
    elide: Text.ElideRight
    font.pixelSize: Style.font.bodySmall
    Accessible.name: text
  }
}
