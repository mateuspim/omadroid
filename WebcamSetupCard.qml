import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model
import "Webcam.js" as Webcam

// v4l2loopback setup guidance, shown while no loopback output exists: what is
// missing, a button that opens the fix in a visible terminal, and the manual
// commands for the clipboard. While a setup runs, outputs are re-scanned.
//
// Public API
//   issue         webcam-devices.sh's reason ("missing-package", …, "scan-error")
//   scanError     the scan's stderr, appended to the detail
//   outputsFound  a loopback output exists; ends the setup polling
//   panelOpen     polling only while the popup is open
//   signal refreshRequested()  scan outputs again
//   copyCommands(), openSetup()
//
// Usage:
//   WebcamSetupCard { issue: "missing-package"; onRefreshRequested: scan() }
Rectangle {
  id: root
  objectName: "omadroidWebcamSetup"
  property string issue: ""
  property string scanError: ""
  property bool outputsFound: false
  property bool panelOpen: true
  property string setupMessage: ""
  property bool setupPending: false
  property double setupStartedAt: 0
  readonly property var guidance: Webcam.webcamSetup(issue)
  readonly property string setupScript: decodeURIComponent(Qt.resolvedUrl("webcam-setup.sh").toString().replace(/^file:\/\//, ""))
  signal refreshRequested

  visible: !outputsFound
  implicitHeight: setupContent.implicitHeight + Style.space(24)
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.urgent, 0.06)
  border.color: Util.alpha(Commons.Color.urgent, 0.4)

  onOutputsFoundChanged: if (outputsFound) {
    setupPending = false;
    setupMessage = "";
  }

  function openSetup() {
    if (guidance.step && !setupLauncher.busy)
      setupLauncher.start(["bash", setupScript, "open", guidance.step], 4);
  }
  function copyCommands() {
    if (guidance.commands && !setupClipboard.busy)
      setupClipboard.start(["wl-copy", "--type", "text/plain"], 4, guidance.commands);
  }

  Command {
    id: setupLauncher
    onFinished: (code, output, error) => {
      if (code === 0) {
        root.setupPending = true;
        root.setupStartedAt = Date.now();
      }
      root.setupMessage = code === 0 ? "Finish setup in the terminal. Outputs will refresh here automatically." :
        "⚠ " + Model.commandError(code, output, error, "webcam setup");
    }
  }
  Timer {
    interval: 3000
    repeat: true
    running: root.setupPending && root.panelOpen && !root.outputsFound
    onTriggered: {
      if (Date.now() - root.setupStartedAt > 300000)
        root.setupPending = false;
      else
        root.refreshRequested();
    }
  }
  Command {
    id: setupClipboard
    onFinished: (code, output, error) => {
      root.setupMessage = code === 0 ? "Commands copied. Paste them into a terminal." :
        "⚠ " + Model.commandError(code, output, error, "copy setup commands");
    }
  }

  ColumnLayout {
    id: setupContent
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: Style.space(12)
    }
    spacing: Style.space(6)
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: "⚠ " + root.guidance.title
      color: Commons.Color.urgent
      font.bold: true
      Accessible.name: text
    }
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: root.guidance.detail + (root.scanError ? " " + root.scanError : "")
      wrapMode: Text.WordWrap
      color: Util.alpha(Commons.Color.foreground, 0.8)
      font.pixelSize: Style.font.bodySmall
    }
    RowLayout {
      Layout.fillWidth: true
      ActionButton {
        text: root.guidance.action
        selected: true
        visible: root.guidance.step !== ""
        enabled: !setupLauncher.busy
        tooltipText: "Open a visible terminal. Installation or module loading starts only when you click."
        onClicked: root.openSetup()
      }
      ActionButton {
        text: "Copy commands"
        visible: root.guidance.commands !== ""
        enabled: !setupClipboard.busy
        tooltipText: "Copy manual setup commands to the clipboard"
        onClicked: root.copyCommands()
      }
    }
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      visible: root.setupMessage !== ""
      text: root.setupMessage
      wrapMode: Text.WordWrap
      color: root.setupMessage.indexOf("⚠") === 0 ? Commons.Color.urgent : Util.alpha(Commons.Color.foreground, 0.8)
      font.pixelSize: Style.font.bodySmall
    }
  }
}
