// Pure projections for the home view (device list, header, session banner).
// Kept apart from Model.js, which is already past the 500-line budget and owns
// parsing; this file only turns Discovery rows into what the list shows.

var GROUP_TITLES = { connected: "CONNECTED", attention: "NEEDS ATTENTION", nearby: "NEARBY" };

/** Which home section a Discovery row belongs to.
 * Example: deviceGroupKey({ source: "adb", status: "offline" }) → "attention"
 * @param {{source: string, status: string}} row @returns {"connected"|"attention"|"nearby"} */
function deviceGroupKey(row) {
  if (row.status === "device") return "connected";
  return row.source === "mdns" ? "nearby" : "attention";
}

/** Split Discovery rows into the home sections, in display order, dropping
 * empty ones. Rows keep Model.deviceRows' order inside a section.
 * Example: deviceGroups([usbReady, mdnsRow]) →
 *   [{ key: "connected", title: "CONNECTED", rows: [usbReady] }, { key: "nearby", … }]
 * @param {Array<object>} rows @returns {Array<{key: string, title: string, rows: Array<object>}>} */
function deviceGroups(rows) {
  var groups = ["connected", "attention", "nearby"].map(function(key) {
    return { key: key, title: GROUP_TITLES[key], rows: [] };
  });
  (Array.isArray(rows) ? rows : []).forEach(function(row) {
    groups.find(function(group) { return group.key === deviceGroupKey(row); }).rows.push(row);
  });
  return groups.filter(function(group) { return group.rows.length > 0; });
}

/** Compact battery text: "64%", with a Nerd Font bolt (󱐋, not the ⚡ emoji) while charging or plugged in.
 * Example: shortBattery({ level: 64, status: 2 }) → "64% 󱐋"
 * @param {{level: number, status: number}|undefined} battery @returns {string} "" when unknown */
function shortBattery(battery) {
  if (!battery || battery.level === undefined) return "";
  // BatteryManager: 2 charging, 4 plugged-not-charging, 5 full (still on power).
  var powered = battery.status === 2 || battery.status === 4 || battery.status === 5;
  return battery.level + "%" + (powered ? " 󱐋" : "");
}

/** "USB", "Wi-Fi" or "Emulator": the transport as people say it. */
function transportName(row) {
  return row.transport === "Wireless" ? "Wi-Fi" : row.transport || "USB";
}

// The short hint for a row that needs the user before it can be used; the
// long how-to stays in Model.statusHint for the device page.
var ATTENTION_HINTS = { unauthorized: "Accept the USB debugging prompt", authorizing: "Accept the USB debugging prompt",
  "no permissions": "USB permission needed", offline: "Offline", connecting: "Connecting…",
  recovery: "In recovery mode", sideload: "In sideload mode", bootloader: "In bootloader", rescue: "In rescue mode" };

/** One concise line under the device name.
 * Example: deviceSubtitle({ status: "device", name: "Desk", model: "Pixel 6", info: { battery: { level: 64, status: 2 } } })
 *   → "Pixel 6 · 64% 󱐋"
 * @param {object} row a Discovery row @returns {string} */
function deviceSubtitle(row) {
  if (row.status === "device") return readySubtitle(row);
  if (row.source === "mdns") return nearbySubtitle(row);
  return ATTENTION_HINTS[row.status] || row.status.charAt(0).toUpperCase() + row.status.slice(1);
}

function readySubtitle(row) {
  var model = row.model && row.model !== row.name ? row.model : transportName(row);
  return [model, shortBattery(row.info && row.info.battery)].filter(Boolean).join(" · ");
}

function nearbySubtitle(row) {
  if (row.pair) return "Wi-Fi · pairing code";
  return [row.model, "Wi-Fi"].filter(Boolean).join(" · ");
}

/** Nerd Font glyph for the row's link: USB plug, Wi-Fi, Wi-Fi off, or a screen for emulators.
 * Example: transportGlyph({ transport: "USB" }) → "󰕓"
 * @param {{transport: string, status: string}} row @returns {string} */
function transportGlyph(row) {
  if (row.transport === "Emulator") return "󰍹";
  if (row.transport !== "Wireless") return "󰕓";
  return row.status === "offline" ? "󰖪" : "󰖩";
}

/** The one inline action a row offers. Ready rows "open" (chevron to the device
 * page); wireless rows that lost their link reconnect, or are dropped when adb
 * has no endpoint to retry. Example: deviceRowAction(mdnsPairRow).kind → "pair"
 * @param {object} row @returns {{kind: ""|"open"|"connect"|"pair"|"reconnect"|"disconnect", label: string, tooltip: string}} */
function deviceRowAction(row) {
  if (row.status === "device") return { kind: "open", label: "›", tooltip: "Open " + row.name };
  if (row.source === "mdns" && row.pair)
    return { kind: "pair", label: "Pair", tooltip: "Pair with the code from Android's Wireless debugging" };
  if (row.source === "mdns")
    return { kind: "connect", label: "Connect", tooltip: "Connect if already paired; opens Pair if it fails" };
  if (row.transport !== "Wireless" || row.status === "connecting") return { kind: "", label: "", tooltip: "" };
  if (row.status === "offline" && row.endpoint)
    return { kind: "reconnect", label: "Reconnect", tooltip: "Reconnect to " + row.endpoint };
  return { kind: "disconnect", label: "Disconnect", tooltip: "Drop this stale wireless entry from adb" };
}

/** Identifiers moved out of the row body into its tooltip.
 * Example: deviceRowTooltip({ source: "adb", serial: "192.168.1.3:5555", endpoint: "192.168.1.3:5555" })
 *   → "Serial 192.168.1.3:5555"
 * @param {object} row @returns {string} */
function deviceRowTooltip(row) {
  var lines = [(row.source === "mdns" ? "Service " : "Serial ") + row.serial];
  if (row.endpoint && row.endpoint !== row.serial) lines.push("Address " + row.endpoint);
  return lines.join("\n");
}

/** Header subtitle for the home view. Example: homeSubtitle(rows) → "2 ready · 1 nearby"
 * @param {Array<object>} rows @returns {string} */
function homeSubtitle(rows) {
  var groups = deviceGroups(rows);
  var count = function(key) {
    var group = groups.find(function(g) { return g.key === key; });
    return group ? group.rows.length : 0;
  };
  var parts = [count("connected") + " ready"];
  if (count("attention")) parts.push(count("attention") + " need attention");
  if (count("nearby")) parts.push(count("nearby") + " nearby");
  return parts.join(" · ");
}

/** Refresh button tooltip: what refresh does plus how fresh the list is.
 * Example: refreshTooltip({ tracking: true, updatedAt: "14:02" }) →
 *   "Refresh devices (F5)\nFollowing devices live · updated 14:02"
 * @param {{busy: boolean, tracking: boolean, updatedAt: string, intervalSec: number}} state @returns {string} */
function refreshTooltip(state) {
  var freshness = state.busy ? "Discovering devices…"
    : state.tracking ? "Following devices live · updated " + (state.updatedAt || "now")
    : "Last scan " + (state.updatedAt || "pending") + " · every " + state.intervalSec + "s";
  return "Refresh devices (F5)\n" + freshness;
}

/** Session banner line. Example: sessionBannerText("webcam", "Desk phone") → "● Webcam · Desk phone"
 * @param {"mirror"|"webcam"|"audio"} kind @param {string} deviceName @returns {string} */
function sessionBannerText(kind, deviceName) {
  var label = ({ webcam: "● Webcam", audio: "♪ Audio" })[kind] || "▶ Mirroring";
  return deviceName ? label + " · " + deviceName : label;
}

/** Banner line while a switch waits for the old session to stop.
 * Example: switchBannerText("webcam") → "Switching to webcam…"
 * @param {"mirror"|"webcam"|"audio"} kind @returns {string} */
function switchBannerText(kind) {
  return "Switching to " + (({ webcam: "webcam", audio: "audio" })[kind] || "mirroring") + "…";
}
