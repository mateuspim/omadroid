// The device page's quick actions. One registry entry per action keeps the
// grid declarative: a new feature is an entry here plus one handler in
// DevicePage.qml's `actionHandlers`, no layout work.

/** Every action the page knows, in grid order. `shows(row)` decides whether
 * the device offers it at all; `enabled(state)` whether it can run right now. */
function actionRegistry() {
  return [
    { key: "mirror", icon: "󰍹", label: "Mirror", ready: true,
      tooltip: function(row, s) { return "Mirror " + row.name + " with scrcpy"; },
      enabled: function(s) { return !s.sessionBusy; },
      selected: function(s) { return s.sessionType === "mirror"; } },
    { key: "audio", icon: "󰓃", label: "Audio", ready: true,
      tooltip: function(row, s) { return "Play this device's sound on the computer, without video"; },
      enabled: function(s) { return !s.sessionBusy; },
      selected: function(s) { return s.sessionType === "audio"; } },
    { key: "wake", icon: "󰖨", ready: true,
      label: function(s) { return s.canUnlock ? "Unlock" : "Wake"; },
      tooltip: function(row, s) { return s.canUnlock ? "Turn the screen on and enter the saved PIN once" : "Turn the screen on"; },
      enabled: function(s) { return !s.powerBusy; } },
    { key: "lock", icon: "󰌾", label: "Lock", ready: true,
      tooltip: function(row, s) { return "Turn the screen off and lock the device, like its power button"; },
      enabled: function(s) { return !s.powerBusy; } },
    { key: "keepAwake", icon: "󰅶", label: "Keep awake", ready: true,
      tooltip: keepAwakeTooltip,
      enabled: function(s) { return s.powerKnown && !s.powerBusy; },
      selected: function(s) { return s.keepAwake; } },
    { key: "sendText", icon: "󰌌", label: "Send text", ready: true,
      tooltip: function(row, s) { return "Type text on this device from the computer's keyboard"; },
      enabled: function(s) { return true; } },
    { key: "goWireless", icon: "󰖩", label: "Go wireless", ready: true,
      shows: function(row) { return row.transport === "USB"; },
      tooltip: function(row, s) { return "Turn on Wireless debugging through this cable and connect over Wi-Fi, so the cable can be unplugged"; },
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
  return s.keepAwake ? "Keep awake is on: the screen stays on, even without mirroring" : "Keep the screen on, even without mirroring. Android's own timeout returns when turned off";
}

/** The quick actions for one discovery row. Actions marked `ready` need an
 * authorized device; Disconnect also works for an offline wireless one.
 * `state` (all optional): { keepAwake, keepAwakeRunning, powerKnown, powerBusy,
 * canUnlock, actionsBusy, sessionBusy, sessionType: "" | "mirror" | "audio" | "webcam" }
 * sessionBusy: a session is starting or stopping (any device); sessionType: the
 * session running on this device, if any.
 * Example: deviceActions({ status: "device", transport: "USB", source: "adb", name: "Phone" }, { powerKnown: true })
 *   → [{ key: "mirror", icon: "󰍹", label: "Mirror", tooltip: "Mirror Phone with scrcpy", enabled: true, selected: false }, …]
 * @param {{status: string, transport: string, source: string, name: string}} row
 * @param {Object} state
 * @returns {Array<{key: string, icon: string, label: string, tooltip: string, enabled: boolean, selected: boolean}>}
 */
function deviceActions(row, state) {
  if (!row || typeof row !== "object")
    throw new Error("deviceActions expects a discovery row {serial, status, transport, source}, got " + JSON.stringify(row));
  var s = actionState(state);
  var ready = row.status === "device";
  return actionRegistry().filter(function(entry) {
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
function actionState(state) {
  var s = state || {};
  return {
    keepAwake: s.keepAwake === true,
    keepAwakeRunning: s.keepAwakeRunning === true,
    powerKnown: s.powerKnown === true,
    powerBusy: s.powerBusy === true,
    canUnlock: s.canUnlock === true,
    actionsBusy: s.actionsBusy === true,
    sessionBusy: s.sessionBusy === true,
    sessionType: String(s.sessionType || "")
  };
}
