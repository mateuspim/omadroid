import Quickshell
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SendText.js" as SendText

// The Send text prompt: device row, typed text, status and the keys that
// drive them. SendText.qml hosts it in a layer-shell window; tests use it
// directly because offscreen Quickshell has no PanelWindow backend.
BorderSurface {
  id: root

  // DiscoveryConsumer or anything with `discovery` and setPreference(name, value).
  property var consumer: null
  // What Enter sends, in order: [{text: "…"} | {key: "ctrl+a"}]. Keys you
  // press are recorded as key steps (chips) instead of acting on the prompt.
  property var steps: []
  // After Ctrl+K the next key is recorded even if the prompt uses it (Backspace, Enter, Esc).
  property bool literalNext: false
  // The device picked with Alt+←/→ while open; "" follows the remembered one.
  property string chosenSerial: ""
  property string status: ""
  readonly property var discovery: consumer ? consumer.discovery : null
  readonly property var allDevices: discovery ? discovery.devices : []
  readonly property var readyDevices: allDevices.filter(row => row.status === "device")
  readonly property string target: SendText.pickTextTarget(allDevices, chosenSerial || (discovery ? discovery.preferences.lastTextTarget : ""))
  readonly property var targetDevice: readyDevices.filter(row => row.serial === target)[0] || null
  readonly property string warning: SendText.unsupportedWarning(SendText.stepsText(steps))
  readonly property bool canSend: target !== "" && warning === "" && !sender.busy
  readonly property string sendScript: decodeURIComponent(Qt.resolvedUrl("scripts/send-text.sh").toString().replace(/^file:\/\//, ""))
  property color foreground: Commons.Color.menu.text
  // Esc on an empty prompt, or a finished send.
  signal dismissed

  height: content.implicitHeight + contentTopInset + contentBottomInset
  radius: Style.cornerRadius
  color: Commons.Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
  padding: Style.spacing.panelPadding

  /** Start over for a new summon. Example: card.reset() */
  function reset() {
    setSteps([]);
    chosenSerial = "";
    Qt.callLater(() => keyCatcher.forceActiveFocus());
  }

  function setSteps(next) {
    steps = next;
    status = "";
    literalNext = false;
  }

  /** Type text at the end of the prompt. Example: card.typeText("hello") */
  function typeText(text) {
    setSteps(SendText.appendText(steps, text));
  }

  /** Record a key chip, by send-text.sh name. Example: card.pressKey("ctrl+a") */
  function pressKey(name) {
    setSteps(SendText.appendKey(steps, name));
  }

  function chooseNext(step) {
    if (readyDevices.length > 1)
      chosenSerial = SendText.cycleTextTarget(allDevices, target, step);
  }

  /** Send the prompt. `clear` selects all and deletes in the device's field
   * first (Ctrl+Enter); `enter` presses Enter after (Shift+Enter). An empty
   * prompt is only sent to clear the field.
   * Example: submit({ clear: true, enter: false }) */
  function submit(options) {
    if (!canSend || (steps.length === 0 && !options.clear))
      return;
    status = "Typing on " + deviceLabel(targetDevice) + "…";
    sender.sentTo = target;
    sender.start(SendText.sendTextCommand(sendScript, target, steps, options), 30);
  }

  // A failed send keeps the prompt open with adb's message, so it can be retried.
  function finishSend(code, error) {
    if (code !== 0) {
      status = "⚠ " + (error.trim() || "Typing failed (exit " + code + ").");
      return;
    }
    consumer.setPreference("lastTextTarget", sender.sentTo);
    dismissed();
  }

  function deviceLabel(row) {
    return row ? row.name || row.serial : "";
  }

  // Ctrl+V and Shift+Insert paste.
  function pastes(event) {
    return (event.key === Qt.Key_V && event.modifiers === Qt.ControlModifier) || (event.key === Qt.Key_Insert && event.modifiers === Qt.ShiftModifier);
  }

  function typedChars(event) {
    if (!event.text || event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
      return "";
    return /[\x00-\x1f\x7f]/.test(event.text) ? "" : event.text;
  }

  function isModifierKey(key) {
    return [Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr].indexOf(key) >= 0;
  }

  // The key after Ctrl+K: modifiers alone wait for the real key.
  function recordLiteral(event) {
    if (isModifierKey(event.key))
      return;
    var name = SendText.recordedKey(event.key, event.modifiers, true);
    literalNext = false;
    name ? pressKey(name) : status = "⚠ That key can't be sent to Android.";
  }

  /** The prompt's own keys come first (send, close, edit, paste, Ctrl+K,
   * Alt+←/→); any other key that doesn't type text is recorded as a chip.
   * @returns {boolean} whether the key was used */
  function handleKey(event) {
    var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier);
    if (literalNext)
      recordLiteral(event);
    else if (event.key === Qt.Key_Escape && !mods)
      steps.length ? setSteps([]) : dismissed();
    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(mods & (Qt.AltModifier | Qt.MetaModifier)))
      submit({ clear: (mods & Qt.ControlModifier) !== 0, enter: (mods & Qt.ShiftModifier) !== 0 });
    else if (event.key === Qt.Key_Backspace && !(mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
      setSteps(SendText.dropLast(steps));
    else if (event.key === Qt.Key_K && mods === Qt.ControlModifier)
      literalNext = true;
    else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && mods === Qt.AltModifier)
      chooseNext(event.key === Qt.Key_Left ? -1 : 1);
    else if (pastes(event))
      typeText(Quickshell.clipboardText || "");
    else if (SendText.recordedKey(event.key, event.modifiers, false))
      pressKey(SendText.recordedKey(event.key, event.modifiers, false));
    else if (typedChars(event))
      typeText(typedChars(event));
    else
      return false;
    return true;
  }

  Command {
    id: sender
    property string sentTo: ""
    onFinished: (code, output, error) => root.finishSend(code, error)
  }

  // Clicks on the card mustn't reach the scrim behind it, which closes.
  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => event.accepted = root.handleKey(event)
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: root.contentTopInset
    anchors.leftMargin: root.contentLeftInset
    anchors.rightMargin: root.contentRightInset
    spacing: Style.spacing.controlPaddingY

    SendTextDevices {
      width: parent.width
      devices: root.readyDevices
      target: root.target
      foreground: root.foreground
    }

    SendTextSteps {
      width: parent.width
      steps: root.steps
      placeholder: "Type on " + (root.deviceLabel(root.targetDevice) || "your device") + "…"
      foreground: root.foreground
      waiting: root.literalNext
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: root.warning || root.status || (root.literalNext ? "Press the key to record, e.g. Backspace or Enter." : "Enter: send  ·  Shift+Enter: send, then Enter  ·  Ctrl+Enter: replace the field\nCtrl+A, Tab, arrows… are recorded as keys  ·  Ctrl+K: record Backspace, Enter or Esc  ·  Alt+←/→: device")
      color: root.foreground
      opacity: root.warning || root.status || root.literalNext ? 1 : 0.58
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }
}
