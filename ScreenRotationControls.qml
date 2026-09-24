import QtQuick
import QtQuick.Layouts
import qs.Commons
import "ScreenRotation.js" as ScreenRotation

ColumnLayout {
  id: root
  required property bool sessionActive
  required property int sessionPid
  required property string deviceSerial
  property int selectedRotation: -1
  property int requestedRotation: -1
  property int requestedPid: 0
  property string requestedSerial: ""
  property bool pendingAutoRotate: false
  property string controlMessage: ""
  property bool controlFailed: false
  readonly property bool controlBusy: setRotation.busy || freeRotation.busy
  spacing: Style.space(4)

  onSessionPidChanged: {
    selectedRotation = -1;
    controlMessage = "";
    controlFailed = false;
  }
  onDeviceSerialChanged: {
    selectedRotation = -1;
    controlMessage = "";
    controlFailed = false;
  }

  function requestRotation(rotation: int): void {
    if (!sessionActive || sessionPid <= 0 || !deviceSerial || controlBusy)
      return;
    requestedPid = sessionPid;
    requestedSerial = deviceSerial;
    requestedRotation = rotation;
    pendingAutoRotate = false;
    controlFailed = false;
    controlMessage = "Locking " + ScreenRotation.orientationLabel(rotation) + "…";
    setRotation.start(ScreenRotation.orientationCommand(requestedSerial, requestedRotation), 5);
  }

  function requestAutoRotate(): void {
    if (!sessionActive || sessionPid <= 0 || !deviceSerial || controlBusy)
      return;
    requestedPid = sessionPid;
    requestedSerial = deviceSerial;
    pendingAutoRotate = true;
    controlFailed = false;
    controlMessage = "Re-enabling auto-rotate…";
    freeRotation.start(ScreenRotation.autoRotateCommand(requestedSerial), 5);
  }

  function finishRotation(exitCode: int, stdoutText: string, stderrText: string): void {
    if (requestedPid !== sessionPid || requestedSerial !== deviceSerial || !sessionActive)
      return;
    var failure = ScreenRotation.orientationFailure(exitCode, stdoutText, stderrText,
      pendingAutoRotate ? "enable auto-rotate" : "lock " + ScreenRotation.orientationLabel(requestedRotation));
    controlFailed = !!failure;
    if (failure) {
      controlMessage = failure;
      return;
    }
    selectedRotation = pendingAutoRotate ? -1 : requestedRotation;
    controlMessage = pendingAutoRotate ? "Auto-rotate enabled." : ScreenRotation.orientationLabel(requestedRotation) + " locked.";
  }

  Command {
    id: setRotation
    onFinished: (code, output, error) => root.finishRotation(code, output, error)
  }
  Command {
    id: freeRotation
    onFinished: (code, output, error) => root.finishRotation(code, output, error)
  }
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.space(6)
    rowSpacing: Style.space(4)
    Repeater {
      model: [
        { rotation: 0, label: "Portrait" },
        { rotation: 1, label: "Landscape (right)" },
        { rotation: 2, label: "Portrait inverted" },
        { rotation: 3, label: "Landscape (left)" }
      ]
      delegate: ActionButton {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        text: modelData.label
        selected: root.selectedRotation === modelData.rotation
        enabled: root.sessionActive && root.sessionPid > 0 && root.deviceSerial !== "" && !root.controlBusy
        tooltipText: "Disable auto-rotate and lock the device to " + modelData.label.toLowerCase()
        Accessible.name: "Lock device to " + modelData.label
        onClicked: root.requestRotation(modelData.rotation)
      }
    }
  }
  ActionButton {
    Layout.fillWidth: true
    text: root.controlBusy ? "Applying…" : "Auto rotate / reset"
    selected: root.selectedRotation < 0 && root.controlMessage === "Auto-rotate enabled."
    enabled: root.sessionActive && root.sessionPid > 0 && root.deviceSerial !== "" && !root.controlBusy
    tooltipText: "Release the device rotation lock and re-enable Android auto-rotate"
    Accessible.name: "Re-enable auto-rotate"
    onClicked: root.requestAutoRotate()
  }
  Label {
    Layout.fillWidth: true
    visible: root.controlMessage !== ""
    text: root.controlMessage
    color: root.controlFailed ? Color.urgent : Color.accent
    wrapMode: Text.WrapAnywhere
    font.pixelSize: Style.font.bodySmall
  }
}
