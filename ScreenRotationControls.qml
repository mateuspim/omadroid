import QtQuick
import QtQuick.Layouts
import qs.Commons
import "ScreenRotation.js" as ScreenRotation

ColumnLayout {
  id: root
  required property bool sessionActive
  required property int sessionPid
  required property string deviceSerial
  required property string sessionScript
  property int selectedRotation: -1
  property bool rotationKnown: false
  property int requestedRotation: -1
  property int requestedPid: 0
  property string requestedSerial: ""
  property bool pendingAutoRotate: false
  property int queriedPid: 0
  property string controlMessage: ""
  property bool controlFailed: false
  readonly property bool controlBusy: setRotation.busy || freeRotation.busy
  spacing: Style.space(4)

  onSessionPidChanged: resetRotationState()
  onDeviceSerialChanged: resetRotationState()
  onSessionActiveChanged: queryRotation()

  function resetRotationState(): void {
    selectedRotation = -1;
    rotationKnown = false;
    controlMessage = "";
    controlFailed = false;
    queryRotation();
  }

  // Android keeps the lock across shell reloads, so read it instead of
  // assuming auto-rotate whenever a new controls instance appears.
  function queryRotation(): void {
    if (!sessionActive || sessionPid <= 0 || !deviceSerial || controlBusy || readRotation.busy)
      return;
    queriedPid = sessionPid;
    readRotation.start(ScreenRotation.rotationQueryCommand(sessionScript), 6);
  }

  function finishQuery(exitCode: int, stdoutText: string, stderrText: string): void {
    if (queriedPid !== sessionPid || !sessionActive || controlBusy)
      return;
    var failure = ScreenRotation.orientationFailure(exitCode, stdoutText, stderrText, "read the device rotation");
    if (failure) {
      controlFailed = true;
      controlMessage = failure;
      return;
    }
    try {
      var state = ScreenRotation.parseRotationState(stdoutText);
      selectedRotation = state.rotation;
      rotationKnown = true;
      controlFailed = false;
      controlMessage = state.rotation < 0 ? "" : ScreenRotation.rotationStateMessage(state.rotation, state.owned);
    } catch (e) {
      controlFailed = true;
      controlMessage = e.message;
    }
  }

  function requestRotation(rotation: int): void {
    if (!sessionActive || sessionPid <= 0 || !deviceSerial || controlBusy)
      return;
    requestedPid = sessionPid;
    requestedSerial = deviceSerial;
    requestedRotation = rotation;
    queriedPid = 0;
    pendingAutoRotate = false;
    controlFailed = false;
    controlMessage = "Locking " + ScreenRotation.orientationLabel(rotation) + "…";
    setRotation.start(ScreenRotation.orientationCommand(sessionScript, requestedRotation), 6);
  }

  function requestAutoRotate(): void {
    if (!sessionActive || sessionPid <= 0 || !deviceSerial || controlBusy)
      return;
    requestedPid = sessionPid;
    requestedSerial = deviceSerial;
    queriedPid = 0;
    pendingAutoRotate = true;
    controlFailed = false;
    controlMessage = "Re-enabling auto-rotate…";
    freeRotation.start(ScreenRotation.autoRotateCommand(sessionScript), 6);
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
    rotationKnown = true;
    controlMessage = ScreenRotation.rotationStateMessage(selectedRotation, true);
  }

  Command {
    id: readRotation
    onFinished: (code, output, error) => root.finishQuery(code, output, error)
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
    selected: root.rotationKnown && root.selectedRotation < 0
    enabled: root.sessionActive && root.sessionPid > 0 && root.deviceSerial !== "" && !root.controlBusy
    tooltipText: "Release the device rotation lock and re-enable Android auto-rotate"
    Accessible.name: "Re-enable auto-rotate"
    onClicked: root.requestAutoRotate()
  }
  Label {
    Layout.fillWidth: true
    visible: root.controlMessage !== ""
    text: (root.controlFailed ? "⚠ " : "") + root.controlMessage
    color: root.controlFailed ? Color.urgent : Color.accent
    wrapMode: Text.WrapAnywhere
    font.pixelSize: Style.font.bodySmall
  }
}
