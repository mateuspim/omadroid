// Device info projections (battery, storage, memory, screen) from
// device-info.sh: shared by QML and the Node fixture tests.

/** Parse device-info.sh output ("serial<TAB>key<TAB>value" lines) into a map.
 * Example: parseDeviceInfo("A\tbattery_level\t71\nA\tinternal\t100:200\n")
 *   → { A: { battery: { level: 71 }, internal: { usedKb: 100, totalKb: 200 }, external: [] } }
 */
function parseDeviceInfo(output) {
  var devices = {};
  String(output).split(/\r?\n/).forEach(function(line) {
    var fields = line.split("\t");
    if (fields.length !== 3 || !fields[0] || !fields[2]) return;
    var info = devices[fields[0]] = devices[fields[0]] || { external: [] };
    var key = fields[1], value = fields[2], number = Number(value);
    var sizes = value.split(":").map(Number);
    if (/^battery_(level|status|temp)$/.test(key) && isFinite(number)) {
      info.battery = info.battery || {};
      info.battery[key.slice(8)] = number;
    } else if (key === "battery_plugged") {
      info.battery = info.battery || {};
      info.battery.plugged = value.split(",");
    } else if (key === "android") info.android = value.slice(0, 16);
    else if (key === "sdk" && isFinite(number)) info.sdk = number;
    else if (key === "mem_kb" && number > 0) info.memKb = number;
    else if (key === "screen" && /^\d+x\d+$/.test(value)) {
      var edges = value.split("x").map(Number);
      info.screen = { width: edges[0], height: edges[1] };
    } else if (key === "internal" && sizes.length === 2 && sizes[1] > 0)
      info.internal = { usedKb: sizes[0], totalKb: sizes[1] };
    else if (/^external_/.test(key)) {
      var parts = value.split(":");
      if (parts.length === 4 && Number(parts[3]) > 0)
        info.external.push({ id: parts[0], kind: parts[1], usedKb: Number(parts[2]), totalKb: Number(parts[3]) });
    }
  });
  return devices;
}

/** Attach each device's parsed info (or null) as `info`. */
function withDeviceInfo(rows, info) {
  return rows.map(function(row) {
    return Object.assign({}, row, { info: info[row.serial] || null });
  });
}

/** Example: formatSize(233775104) → "239 GB"; formatSize(999842816) → "1.02 TB" (1000-based, like Android's Settings). */
function formatSize(kb) {
  var bytes = kb * 1024, gb = bytes / 1e9;
  if (gb >= 1000) return String(Math.round(gb / 10) / 100) + " TB";
  if (gb >= 100) return Math.round(gb) + " GB";
  if (gb >= 1) return String(Math.round(gb * 10) / 10) + " GB";
  return Math.round(bytes / 1e6) + " MB";
}

/** Long-edge-first aspect ratio, snapped to the common names within 1 %.
 * Example: aspectRatio(1600, 2560) → "16:10"; aspectRatio(1080, 2400) → "20:9"
 */
function aspectRatio(width, height) {
  var long = Math.max(width, height), short = Math.min(width, height);
  if (!short) return "";
  var ratio = long / short;
  var named = [[4, 3], [3, 2], [16, 10], [5, 3], [16, 9], [18, 9], [19, 9], [19.5, 9], [20, 9], [21, 9]].find(function(pair) {
    return Math.abs(ratio - pair[0] / pair[1]) / ratio < 0.01;
  });
  if (named) return named[0] + ":" + named[1];
  var gcd = function(a, b) { return b ? gcd(b, a % b) : a; }, d = gcd(long, short);
  return long / d <= 32 ? long / d + ":" + short / d : ratio.toFixed(2) + ":1";
}

/** Example: batteryLabel({ level: 71, status: 2, plugged: ["usb"] }) → "71 % · charging" */
function batteryLabel(battery) {
  if (!battery || battery.level === undefined) return "";
  var state = ({ 2: "charging", 3: "on battery", 4: "plugged in, not charging", 5: "full" })[battery.status] || "";
  return battery.level + " %" + (state ? " · " + state : "");
}

function storageLabel(storage) {
  return formatSize(storage.usedKb) + " of " + formatSize(storage.totalKb) + " used (" + Math.round(100 * storage.usedKb / storage.totalKb) + " %)";
}

/** Label/value pairs for the device page's Info section, omitting anything unread. */
function deviceDetails(info) {
  if (!info) return [];
  var rows = [];
  if (info.battery && info.battery.level !== undefined) {
    var sources = { ac: "AC", usb: "USB", wireless: "wireless" };
    var plugged = (info.battery.plugged || []).map(function(source) { return sources[source] || source; }).join(", ");
    rows.push({ label: "Battery", value: batteryLabel(info.battery) + (plugged ? " (" + plugged + ")" : "") +
      (info.battery.temp !== undefined ? " · " + (info.battery.temp / 10).toFixed(1) + " °C" : "") });
  }
  if (info.android) rows.push({ label: "Android", value: info.android + (info.sdk ? " (SDK " + info.sdk + ")" : "") });
  if (info.internal) rows.push({ label: "Internal storage", value: storageLabel(info.internal) });
  var names = { sd: "SD card", usb: "USB drive", external: "External storage" };
  (info.external || []).forEach(function(volume) {
    var sameKind = info.external.filter(function(other) { return other.kind === volume.kind; }).length > 1;
    rows.push({ label: (names[volume.kind] || names.external) + (sameKind ? " " + volume.id : ""), value: storageLabel(volume) });
  });
  if (info.memKb) rows.push({ label: "Memory", value: formatSize(info.memKb) });
  if (info.screen) rows.push({ label: "Screen", value: info.screen.width + " × " + info.screen.height + " · " + aspectRatio(info.screen.width, info.screen.height) });
  return rows;
}
