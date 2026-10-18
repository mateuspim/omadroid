.import "Model.js" as Model

// The device page's two registries: session kinds (the big Mirror · Audio ·
// Webcam cards, one scrcpy session at a time) and device controls (the
// compact row under them). One entry per feature keeps the page declarative:
// a new session kind is an entry in sessionRegistry() plus a launch in
// DeviceSessions.qml's `startHandlers`; a new control is an entry in
// controlRegistry() plus one handler in DevicePage.qml's `controlHandlers`.

var resolutionNames = { "0": "Native", "720": "720 px", "1080": "1080 px", "1440": "1440 px", "1920": "1080p", "2560": "1440p", "3840": "4K" };
var cameraSizeNames = { "3840x2160": "4K", "2560x1440": "1440p", "1920x1080": "1080p", "1280x720": "720p" };

/** Every session kind, in card order. `summary(forms)` describes what a click
 * would start, from the option forms' current state; `blocked(forms)` names
 * why it can't start yet (the click then opens its options instead);
 * `running` is how a switch hint names a session of this kind. */
function sessionRegistry() {
  return [
    { key: "mirror", icon: "󰍹", label: "Mirror", running: "mirroring",
      tooltip: "Mirror the screen in a scrcpy window",
      summary: function(f) { return mirrorSummary(f.profileName, f.profile); } },
    { key: "audio", icon: "󰓃", label: "Audio", running: "audio",
      tooltip: "Play this device's sound on the computer, without video",
      summary: function(f) { return audioSummary(f.profile); } },
    { key: "webcam", icon: "󰖠", label: "Webcam", running: "the webcam",
      tooltip: "Use a phone camera as this computer's webcam",
      summary: function(f) { return webcamCardSummary(f.webcam, f.cameras); },
      blocked: function(f) { return f.webcamIssue ? "Set up a webcam output first" : ""; } }
  ];
}

/** Mirror card summary: profile, resolution, bitrate, and recording.
 * Example: mirrorSummary("Balanced", { maxSize: "1920", bitrate: "8", record: false }) → "Balanced · 1080p · 8 Mbps" */
function mirrorSummary(profileName, profile) {
  if (!profile) return "";
  var parts = [profileName, resolutionNames[profile.maxSize] || profile.maxSize + " px", profile.bitrate + " Mbps"];
  return parts.concat(profile.record ? ["Rec"] : []).join(" · ");
}

/** Audio card summary: scrcpy's default codec (Opus) and whether it records.
 * Example: audioSummary({ record: true }) → "Opus · records MKA" */
function audioSummary(profile) {
  return profile && profile.record ? "Opus · records MKA" : "Opus · no video";
}

/** Webcam card summary: the camera (by facing when the list is known) and
 * the size and rate. Example: webcamCardSummary({ camera: "id:1", size: "1920x1080", fps: "30" },
 *   [{ id: "1", facing: "front" }]) → "Front · 1080p · 30 fps" */
function webcamCardSummary(webcam, cameras) {
  if (!webcam) return "";
  var size = webcam.size === "auto" ? "Auto" : cameraSizeNames[webcam.size] || webcam.size.replace("x", "×");
  return [cameraShortName(webcam.camera, cameras), size, webcam.fps + " fps"].join(" · ");
}

/** Example: cameraShortName("back", null) → "Back"; cameraShortName("id:2", null) → "Camera 2" */
function cameraShortName(choice, cameras) {
  var camera = Model.chosenCamera(cameras, choice);
  var facing = camera ? camera.facing : choice;
  if (facing === "front" || facing === "back" || facing === "external")
    return facing.charAt(0).toUpperCase() + facing.slice(1);
  return "Camera " + String(choice).replace(/^id:/, "");
}

/** The session cards for one ready device.
 * `state`: { serial, missingTools, armed (the kind awaiting a recording
 * confirm, or ""), forms: {profileName, profile, webcam, cameras, webcamIssue},
 * session: {busy, pid (0 while starting), serial, kind, stopping, recording, pendingKind,
 * pendingSerial, deviceName} } — `session` is the machine's one session, on
 * any device; deviceName names its device for the switch hint.
 * Each card: { key, icon, label, subtitle, tooltip, enabled, running, urgent,
 * action: "start" | "stop" | "arm" | "options" | "none" }.
 * Example: sessionCards({ serial: "USB123", forms: {...}, session: { busy: false } })[0]
 *   → { key: "mirror", subtitle: "Balanced · 1080p · 8 Mbps", action: "start", enabled: true, … } */
function sessionCards(state) {
  if (!state || typeof state.serial !== "string" || !state.forms || !state.session)
    throw new Error("sessionCards expects {serial, forms, session}, got " + JSON.stringify(state));
  return sessionRegistry().map(function(entry) {
    var summary = entry.summary(state.forms);
    var card = cardState(entry, state);
    return {
      key: entry.key,
      icon: entry.icon,
      label: entry.label,
      subtitle: card.hint || summary,
      tooltip: card.tooltip || entry.tooltip + (summary ? " · " + summary : ""),
      enabled: card.action !== "none" || card.running === true,
      running: card.running === true,
      urgent: card.urgent === true,
      action: card.action
    };
  });
}

/** What one card does now; the first rule that applies wins. */
function cardState(entry, state) {
  var s = state.session;
  if (s.pendingKind)
    return pendingCard(entry, state);
  // Nothing switches until the starting session runs (a switch stops a pid).
  if (s.busy && !s.stopping && !(s.pid > 0))
    return startingCard(entry, state);
  if (s.busy && s.serial === state.serial && s.kind === entry.key)
    return s.stopping ? { hint: "Stopping…", action: "none", running: true } : { hint: "● Running", action: "stop", running: true, tooltip: "Stop " + entry.running };
  if (state.missingTools)
    return { action: "none", tooltip: "Install " + state.missingTools + " first" };
  var blocked = entry.blocked ? entry.blocked(state.forms) : "";
  if (blocked)
    return { hint: "Needs setup", action: "options", tooltip: blocked };
  return s.busy ? switchCard(entry, state) : { action: "start" };
}

/** While a session starts, its own card says so and the others wait. */
function startingCard(entry, state) {
  var s = state.session;
  if (s.serial === state.serial && s.kind === entry.key)
    return { hint: "Starting…", action: "none", running: true, tooltip: "Starting " + entry.running };
  return { action: "none", tooltip: "Wait for the session to start" };
}

/** While a switch waits for the old session to stop, only its target speaks. */
function pendingCard(entry, state) {
  var s = state.session;
  if (s.pendingKind === entry.key && s.pendingSerial === state.serial)
    return { hint: "Switching…", action: "none", running: true, tooltip: "Starts once the running session has stopped" };
  return { action: "none", tooltip: "Wait for the switch to finish" };
}

/** Another session runs (other kind, or another device): a click switches.
 * A recording needs a second click, so it isn't cut short by accident. */
function switchCard(entry, state) {
  var s = state.session;
  if (s.stopping)
    return { action: "none", tooltip: "Wait for the running session to stop" };
  var elsewhere = s.serial !== state.serial;
  var device = s.deviceName || s.serial;
  // The card has two short lines: another device is named instead of the
  // kind (the banner shows that); the tooltip says both.
  var hint = "Switch · stops " + (elsewhere ? device : runningName(s.kind));
  var stops = "Switch · stops " + runningName(s.kind) + (elsewhere ? " on " + device : "");
  if (!s.recording)
    return { hint: hint, action: "start", tooltip: stops };
  if (state.armed === entry.key)
    return { hint: "Stop recording & switch?", action: "start", urgent: true, tooltip: "Click again to finalize the recording and switch" };
  return { hint: hint, action: "arm", tooltip: stops + " · its recording is finalized" };
}

/** Example: runningName("webcam") → "the webcam" */
function runningName(kind) {
  var entry = sessionRegistry().find(function(e) { return e.key === kind; });
  return entry ? entry.running : "the session";
}

/** Every device control, in row order. `shows(row)` decides whether the
 * device offers it at all; `enabled(state)` whether it can run right now. */
function controlRegistry() {
  return [
    { key: "wake", icon: "󰖨", ready: true,
      label: function(s) { return s.canUnlock ? "Unlock" : "Wake"; },
      tooltip: function(row, s) { return s.canUnlock ? "Turn the screen on and enter the saved PIN once" : "Turn the screen on"; },
      enabled: function(s) { return !s.powerBusy; } },
    { key: "lock", icon: "󰌾", label: "Lock", ready: true,
      tooltip: function(row, s) { return "Turn the screen off and lock the device, like its power button"; },
      enabled: function(s) { return !s.powerBusy; } },
    { key: "keepAwake", icon: "󰅶", label: "Awake", ready: true,
      tooltip: keepAwakeTooltip,
      enabled: function(s) { return s.powerKnown && !s.powerBusy; },
      selected: function(s) { return s.keepAwake; } },
    { key: "sendText", icon: "󰌌", label: "Text", ready: true,
      tooltip: function(row, s) { return "Send text: type on this device from the computer's keyboard"; },
      enabled: function(s) { return true; } },
    { key: "goWireless", icon: "󰖩", label: "Wireless", ready: true,
      shows: function(row) { return row.transport === "USB"; },
      tooltip: function(row, s) { return "Go wireless: turn on Wireless debugging through this cable and connect over Wi-Fi, so the cable can be unplugged"; },
      enabled: function(s) { return !s.actionsBusy; } },
    { key: "disconnect", icon: "󰖪", label: "Disconnect", ready: false,
      shows: function(row) { return row.source === "adb" && row.transport === "Wireless"; },
      tooltip: function(row, s) { return s.sessionType ? "Stop this device's session first" : "Disconnect this wireless ADB connection"; },
      enabled: function(s) { return !s.actionsBusy && !s.sessionType; } }
  ];
}

function keepAwakeTooltip(row, s) {
  if (s.keepAwake && !s.keepAwakeRunning)
    return "Keep awake is on, but not running; it restarts when the device reconnects";
  return s.keepAwake ? "Keep awake is on: the screen stays on, even without mirroring" : "Keep awake: the screen stays on, even without mirroring. Android's own timeout returns when turned off";
}

/** The device controls for one discovery row. Controls marked `ready` need an
 * authorized device; Disconnect also works for an offline wireless one.
 * `state` (all optional): { keepAwake, keepAwakeRunning, powerKnown, powerBusy,
 * canUnlock, actionsBusy, sessionType: "" | "mirror" | "audio" | "webcam" }
 * sessionType: the session running on this device, if any.
 * Example: deviceControls({ status: "device", transport: "USB", source: "adb", name: "Phone" }, { powerKnown: true })
 *   → [{ key: "wake", icon: "󰖨", label: "Wake", tooltip: "Turn the screen on", enabled: true, selected: false }, …]
 * @param {{status: string, transport: string, source: string, name: string}} row
 * @param {Object} state
 * @returns {Array<{key: string, icon: string, label: string, tooltip: string, enabled: boolean, selected: boolean}>}
 */
function deviceControls(row, state) {
  if (!row || typeof row !== "object")
    throw new Error("deviceControls expects a discovery row {serial, status, transport, source}, got " + JSON.stringify(row));
  var s = controlState(state);
  var ready = row.status === "device";
  return controlRegistry().filter(function(entry) {
    return (ready || !entry.ready) && (!entry.shows || entry.shows(row));
  }).map(function(entry) {
    return {
      key: entry.key,
      icon: entry.icon,
      label: typeof entry.label === "function" ? entry.label(s) : entry.label,
      tooltip: entry.tooltip(row, s),
      enabled: entry.enabled(s) === true,
      selected: entry.selected ? entry.selected(s) === true : false
    };
  });
}

/** Fill in the defaults so registry entries can read every field. */
function controlState(state) {
  var s = state || {};
  return {
    keepAwake: s.keepAwake === true,
    keepAwakeRunning: s.keepAwakeRunning === true,
    powerKnown: s.powerKnown === true,
    powerBusy: s.powerBusy === true,
    canUnlock: s.canUnlock === true,
    actionsBusy: s.actionsBusy === true,
    sessionType: String(s.sessionType || "")
  };
}
