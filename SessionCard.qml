import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The running session's controls: what runs and where, Preview (webcam),
// Log and Stop, battery, recording, the last message, the webcam's
// Apply offer and preview, and the mirror's screen power and rotation.
//
// Public API
//   session        MirrorSession (required)
//   device         the session device's discovery row, or null
//   panelOpen      the card is on screen; the preview only decodes then
//   webcamChanged  settings differ from the running webcam: offer Apply
//   previewOpen    webcam preview shown (Preview toggles it)
//   compact        smaller preview, e.g. while options are unfolded below
//   signal applyRequested()  the Apply button was pressed
//
// Usage:
//   SessionCard { session: mirrorSession; device: row; onApplyRequested: options.applyWebcam() }
Rectangle {
  id: root
  objectName: "omadroidSessionCard"
  required property var session
  property var device: null
  property bool panelOpen: true
  property bool webcamChanged: false
  property bool previewOpen: false
  property bool compact: false
  signal applyRequested

  readonly property bool isWebcam: session.sessionType === "webcam"
  readonly property bool isMirror: session.sessionType === "mirror"
  // Only the card on screen drives the phone: a hidden one (another page)
  // would query or change rotation behind the visible one.
  readonly property bool controlsActive: session.busy && !session.stopping && isMirror && visible
  // The Android device name (or model) when discovery knows the device; the
  // serial (IP:port for wireless) otherwise, and always in the tooltip.
  readonly property string deviceName: device ? device.name : session.sessionSerial
  readonly property string deviceAddress: device ? [device.model !== device.name ? device.model : "", device.transport, session.sessionSerial].filter(Boolean).join(" · ") : session.sessionSerial
  readonly property var battery: device && device.info ? device.info.battery : null

  implicitHeight: content.implicitHeight + Style.space(24)
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.accent, 0.06)
  border.color: Util.alpha(Commons.Color.accent, 0.4)

  ColumnLayout {
    id: content
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: Style.space(12)
    }
    spacing: Style.space(6)
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      ColumnLayout {
        Layout.fillWidth: true
        // A wrapped label reports its unwrapped width; with the buttons
        // beside it, that could widen the popup.
        Layout.preferredWidth: 1
        spacing: 0
        Label {
          Layout.fillWidth: true
          text: (root.session.sessionPid > 0 ? "● " : "") + root.session.sessionTitle
          color: Commons.Color.accent
          font.bold: true
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          Accessible.name: text + ", " + root.deviceName
        }
        Label {
          Layout.fillWidth: true
          text: [root.deviceName, root.battery ? Model.batteryLabel(root.battery) : ""].filter(Boolean).join(" · ")
          color: Util.alpha(Commons.Color.foreground, 0.7)
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          Controls.ToolTip.text: root.deviceAddress
          Controls.ToolTip.visible: nameHover.hovered && root.deviceAddress !== ""
          HoverHandler {
            id: nameHover
          }
        }
      }
      ActionButton {
        text: root.previewOpen ? "Hide" : "Preview"
        visible: root.isWebcam
        enabled: root.session.sessionPid > 0 && root.session.sessionSink !== ""
        tooltipText: "Show what video apps receive from " + root.session.sessionSink
        onClicked: root.previewOpen = !root.previewOpen
      }
      ActionButton {
        text: "Log"
        tooltipText: "Show or hide the hidden terminal running scrcpy"
        onClicked: root.session.toggleLog()
      }
      ActionButton {
        text: root.session.stopping ? "Stopping…" : "Stop"
        selected: true
        enabled: root.session.sessionPid > 0 && !root.session.stopping
        tooltipText: root.session.stopLabel + " · a clean shutdown, so recordings finalize"
        Accessible.name: root.session.stopLabel
        onClicked: root.session.stop()
      }
    }
    Label {
      Layout.fillWidth: true
      visible: root.session.sessionRecording !== ""
      text: "● Recording · " + root.session.sessionRecording
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 2
      elide: Text.ElideRight
      color: Util.alpha(Commons.Color.foreground, 0.7)
      font.pixelSize: Style.font.bodySmall
      Accessible.name: text
    }
    Label {
      Layout.fillWidth: true
      visible: root.session.message !== ""
      text: (root.session.failed ? "⚠ " : "") + root.session.message
      color: root.session.failed ? Commons.Color.urgent : Commons.Color.accent
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 3
      elide: Text.ElideRight
      font.pixelSize: Style.font.bodySmall
      Accessible.name: text
    }
    RowLayout {
      objectName: "omadroidWebcamApply"
      Layout.fillWidth: true
      visible: root.webcamChanged
      Label {
        Layout.fillWidth: true
        // A wrapped label still reports its unwrapped width as implicit.
        Layout.preferredWidth: 1
        text: "Settings changed since start."
        wrapMode: Text.WordWrap
        color: Util.alpha(Commons.Color.foreground, 0.7)
        font.pixelSize: Style.font.bodySmall
      }
      ActionButton {
        text: "Apply · restart"
        selected: true
        enabled: !root.session.restartPending
        tooltipText: "Restart the webcam with the new settings; video apps see a short gap"
        onClicked: root.applyRequested()
      }
    }
    // Only while visible: an open preview keeps reading and decoding frames.
    Loader {
      id: previewLoader
      objectName: "omadroidWebcamPreview"
      Layout.fillWidth: true
      active: root.previewOpen && root.isWebcam && root.session.sessionPid > 0 && !root.session.stopping && root.panelOpen && root.session.sessionSink !== ""
      // Named: Loader.status, not the session's status.
      visible: active && previewLoader.status === Loader.Ready
      source: "WebcamPreview.qml"
      onLoaded: {
        item.device = Qt.binding(() => root.session.sessionSink);
        item.runtimeDir = Qt.binding(() => root.session.runtimeDir);
        // Small while the options below are open, so both fit the popup.
        item.maxHeight = Qt.binding(() => root.compact ? 160 : 320);
      }
    }
    Label {
      Layout.fillWidth: true
      visible: previewLoader.active && previewLoader.status === Loader.Error
      text: "⚠ The preview could not load. Check the shell log for WebcamPreview.qml."
      color: Commons.Color.urgent
      wrapMode: Text.WordWrap
    }
    ScreenPowerControls {
      Layout.fillWidth: true
      visible: root.isMirror
      sessionActive: root.controlsActive
      sessionPid: root.session.sessionPid
    }
    ScreenRotationControls {
      Layout.fillWidth: true
      visible: root.isMirror
      sessionActive: root.controlsActive
      sessionPid: root.session.sessionPid
      deviceSerial: root.session.sessionSerial
      sessionScript: root.session.sessionScript
    }
  }
}
