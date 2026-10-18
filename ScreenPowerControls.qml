import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "ScreenPower.js" as ScreenPower

ColumnLayout {
  id: root
  required property int sessionPid
  required property bool sessionActive
  property int requestedPid: 0
  property bool requestedScreenOn: false
  property string controlMessage: ""
  property string pressFailure: ""
  property bool controlFailed: false
  readonly property bool controlBusy: keyPress.busy || releaseDelay.running || keyRelease.busy
  spacing: Style.space(4)

  onSessionPidChanged: {
    controlMessage = "";
    controlFailed = false;
  }

  // Example: requestScreenPower(true) lights the phone for local authentication.
  function requestScreenPower(screenOn: bool): void {
    if (!sessionActive || sessionPid <= 0 || controlBusy)
      return;
    requestedPid = sessionPid;
    requestedScreenOn = screenOn;
    pressFailure = "";
    controlFailed = false;
    controlMessage = "Sending screen-" + (screenOn ? "on" : "off") + " request…";
    keyPress.start(ScreenPower.screenPowerKeyCommand(requestedPid, screenOn, true), 3);
  }

  // Release even after an ambiguous timeout: the compositor may have received down.
  // Omarchy's clipboard binding uses this split for Hyprland discussion #14099.
  function finishPowerPress(exitCode: int, stdoutText: string, stderrText: string): void {
    pressFailure = ScreenPower.screenPowerFailure(exitCode, stdoutText, stderrText);
    releaseDelay.restart();
  }

  // Example: finishPowerRelease(0, "ok\n", "") acknowledges dispatch, not phone state.
  function finishPowerRelease(exitCode: int, stdoutText: string, stderrText: string): void {
    if (requestedPid !== sessionPid || !sessionActive)
      return;
    var releaseFailure = ScreenPower.screenPowerFailure(exitCode, stdoutText, stderrText);
    controlFailed = !!(pressFailure || releaseFailure);
    controlMessage = pressFailure || releaseFailure || (requestedScreenOn ? "Screen-on request sent. Complete authentication on your phone." : "Screen-off request sent. Mirroring continues.");
  }

  Command {
    id: keyPress
    onFinished: (code, output, error) => root.finishPowerPress(code, output, error)
  }
  Timer {
    id: releaseDelay
    interval: 50
    onTriggered: keyRelease.start(ScreenPower.screenPowerKeyCommand(root.requestedPid, root.requestedScreenOn, false), 3)
  }
  Command {
    id: keyRelease
    onFinished: (code, output, error) => root.finishPowerRelease(code, output, error)
  }
  RowLayout {
    Layout.fillWidth: true
    ActionButton {
      Layout.fillWidth: true
      text: "Phone screen on"
      enabled: root.sessionActive && root.sessionPid > 0 && !root.controlBusy
      tooltipText: "Show the physical screen for a password or fingerprint prompt"
      Accessible.name: "Turn phone screen on"
      onClicked: root.requestScreenPower(true)
    }
    ActionButton {
      Layout.fillWidth: true
      text: "Phone screen off"
      enabled: root.sessionActive && root.sessionPid > 0 && !root.controlBusy
      tooltipText: "Darken the physical display again without restarting mirroring"
      Accessible.name: "Turn phone screen off"
      onClicked: root.requestScreenPower(false)
    }
  }
  Label {
    Layout.fillWidth: true
    visible: root.controlMessage !== ""
    text: (root.controlFailed ? "⚠ " : "") + root.controlMessage
    color: root.controlFailed ? Commons.Color.urgent : Commons.Color.accent
    wrapMode: Text.WrapAnywhere
    font.pixelSize: Style.font.bodySmall
  }
}
