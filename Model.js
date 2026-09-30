// Pure projections: shared by QML and the Node fixture tests.
function endpoint(value) {
  var text = String(value || "").trim();
  var match = /^(\[[0-9a-fA-F:.%a-zA-Z0-9_-]+\]|[a-zA-Z0-9][a-zA-Z0-9.-]*):(\d{1,5})$/.exec(text);
  if (!match || Number(match[2]) < 1 || Number(match[2]) > 65535) return "";
  if (/^[\d.]+$/.test(match[1]) && (match[1].split(".").length !== 4 || match[1].split(".").some(function(part) { return !part || Number(part) > 255; }))) return "";
  return match[1] + ":" + Number(match[2]);
}

function endpointParts(value) {
  var address = endpoint(value);
  if (!address) return { host: "", port: "" };
  var separator = address.lastIndexOf(":");
  return { host: address.slice(0, separator), port: address.slice(separator + 1) };
}

function pairingEndpoint(host, port) {
  var pairingHost = String(host || "").trim();
  if (pairingHost[0] !== "[" && pairingHost.indexOf(":") >= 0)
    pairingHost = "[" + pairingHost + "]";
  return endpoint(pairingHost + ":" + String(port || "").trim());
}

function pairingPrefill(row, rows) {
  var selected = endpointParts(row && row.endpoint);
  var pairing = row && row.pair ? row : (Array.isArray(rows) ? rows : []).find(function(candidate) {
    return candidate.pair && endpointParts(candidate.endpoint).host === selected.host;
  });
  var pairingAddress = endpointParts(pairing && pairing.endpoint);
  return { host: selected.host || pairingAddress.host, port: pairingAddress.port };
}

/** Find the connect endpoint Android advertises on the host that was just paired.
 * Pairing and connection use different ports, so the pairing address cannot be reused.
 * Example: connectEndpointAfterPairing("192.168.1.5:42000", rows) → "192.168.1.5:37002"
 * @param {string} pairedAddress @param {Array<object>} rows @returns {string} "" when none is known */
function connectEndpointAfterPairing(pairedAddress, rows) {
  var host = endpointParts(pairedAddress).host;
  if (!host) return "";
  var match = (Array.isArray(rows) ? rows : []).find(function(row) {
    return !row.pair && row.service === "_adb-tls-connect._tcp" && endpointParts(row.endpoint).host === host;
  });
  return match ? match.endpoint : "";
}

function needsPairingFallback(row, connectFailed) {
  return !!connectFailed && !!row && row.source === "mdns" && !row.pair &&
    row.transport === "Wireless" && endpoint(row.endpoint) !== "";
}

function serviceId(value) {
  return String(value).replace(/\._adb(?:-tls-connect|-tls-pairing)?\._tcp\.?(?:local\.?)?$/, "");
}

function parseDevices(output) {
  var seen = {};
  return String(output).split(/\r?\n/).reduce(function(rows, line) {
    var match = /^(\S+)\s+(device|offline|unauthorized|authorizing|connecting|recovery|sideload|bootloader|rescue|host|no permissions|unknown)(?:\s|$)(.*)$/.exec(line.trim());
    if (!match || seen[match[1]]) return rows;
    seen[match[1]] = true;
    var serial = match[1], fields = {};
    match[3].split(/\s+/).forEach(function(field) {
      var i = field.indexOf(":");
      if (i > 0) fields[field.slice(0, i)] = field.slice(i + 1);
    });
    var wireless = !!endpoint(serial) || /\._adb.*\._tcp/.test(serial);
    rows.push({ key: "adb:" + serial, name: (fields.model || fields.device || serial).replace(/_/g, " "),
      serial: serial, status: match[2], transport: fields.usb ? "USB" : wireless ? "Wireless" : /^emulator-/.test(serial) ? "Emulator" : "USB",
      endpoint: endpoint(serial), service: "", source: "adb", pair: false });
    return rows;
  }, []);
}

function parseMdns(output) {
  var seen = {};
  return String(output).split(/\r?\n/).reduce(function(rows, line) {
    // Avahi parsable format: =;interface;protocol;name;type;domain;host;address;port.
    // Names escape delimiter/control bytes as decimal \\DDD sequences.
    var fields = line.split(";");
    if (fields.length < 9 || fields[0] !== "=" || !/^_adb(?:-tls-connect|-tls-pairing)?\._tcp\.?$/.test(fields[4])) return rows;
    var name;
    try {
      name = decodeURIComponent(fields[3].replace(/%/g, "%25").replace(/\\(\d{3})/g, function(_, code) {
        return "%" + ("0" + Number(code).toString(16)).slice(-2);
      }));
    } catch (_) { name = fields[3]; }
    var type = fields[4].replace(/\.$/, "");
    var host = fields[7];
    if (host.indexOf(":") >= 0) {
      // Link-local IPv6 needs the interface scope to be usable by adb connect.
      if (/^fe[89ab][0-9a-f]:/i.test(host) && host.indexOf("%") < 0) host += "%" + fields[1];
      host = "[" + host + "]";
    }
    var address = endpoint(host + ":" + fields[8]);
    if (!address || !name) return rows;
    var key = "mdns:" + type + ":" + address;
    if (seen[key]) return rows;
    seen[key] = true;
    var pair = type === "_adb-tls-pairing._tcp";
    // TXT is the rest of the line: "api=36.1" "name=SM-X730" "v=1".
    var model = (/"name=([^"]*)"/.exec(fields.slice(9).join(";")) || [])[1] || "";
    rows.push({ key: key, name: serviceId(name), serial: name, model: model, status: pair ? "pairing" : "discovered",
      transport: "Wireless", endpoint: address, service: type, source: "mdns", pair: pair });
    return rows;
  }, []);
}

/** Parse device-names.sh output ("serial<TAB>name" lines) into a map.
 * Example: parseDeviceNames("USB123\tDesk phone\n") → { USB123: "Desk phone" }
 */
function parseDeviceNames(output) {
  var names = {};
  String(output).split(/\r?\n/).forEach(function(line) {
    var i = line.indexOf("\t");
    if (i > 0 && line.slice(i + 1).trim()) names[line.slice(0, i)] = line.slice(i + 1).trim();
  });
  return names;
}

/** Prefer the Android device name over the model code, keeping the model.
 * Example: withDeviceNames([{ serial: "A", name: "SM X730" }], { A: "Desk tablet" })
 *   → [{ serial: "A", name: "Desk tablet", model: "SM X730" }]
 */
function withDeviceNames(rows, names) {
  return rows.map(function(row) {
    return Object.assign({}, row, { model: row.name, name: names[row.serial] || row.name });
  });
}

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

/** Example: formatSize(233775104) → "223 GB"; formatSize(11788072) → "11.2 GB" (1024-based, like df -h). */
function formatSize(kb) {
  var gb = kb / 1048576;
  if (gb >= 100) return Math.round(gb) + " GB";
  if (gb >= 1) return String(Math.round(gb * 10) / 10) + " GB";
  return Math.round(kb / 1024) + " MB";
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

/** One-line card summary. Example: "Battery 71 % · Android 16 · 127/223 GB used" */
function deviceSummary(info) {
  if (!info) return "";
  var parts = [];
  if (info.battery && info.battery.level !== undefined)
    parts.push("Battery " + info.battery.level + " %" + (info.battery.status === 2 ? " (charging)" : ""));
  if (info.android) parts.push("Android " + info.android);
  if (info.internal) parts.push(formatSize(info.internal.usedKb).replace(/ GB$/, "") + "/" + formatSize(info.internal.totalKb) + " used");
  return parts.join(" · ");
}

/** Label/value pairs for the expanded device card, omitting anything unread. */
function deviceDetails(info) {
  if (!info) return [];
  var rows = [];
  if (info.battery && info.battery.level !== undefined) {
    var sources = { ac: "charger", usb: "USB", wireless: "wireless" };
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

function deviceRows(devices, services) {
  var rows = devices.map(function(row) { return Object.assign({}, row); });
  services.forEach(function(service) {
    var existing = !service.pair && rows.find(function(row) {
      return row.source === "adb" && row.transport === "Wireless" &&
        ((row.endpoint && row.endpoint === service.endpoint) || serviceId(row.serial) === serviceId(service.serial));
    });
    if (existing) {
      existing.endpoint = service.endpoint;
      existing.service = service.service;
    } else rows.push(service);
  });
  return rows.sort(function(a, b) {
    var rank = function(row) { return row.status === "device" ? 0 : row.source === "adb" ? 1 : row.pair ? 3 : 2; };
    return rank(a) - rank(b) || a.name.localeCompare(b.name) || a.key.localeCompare(b.key);
  });
}

function statusLabel(status) {
  return ({ device: "Ready", unauthorized: "Authorization needed", offline: "Offline", "no permissions": "USB permission needed",
    discovered: "Available to connect", pairing: "Pairing available" })[status] || status.charAt(0).toUpperCase() + status.slice(1);
}

function statusHint(row) {
  if (row.status === "unauthorized" || row.status === "authorizing") return "Unlock Android and accept the USB debugging prompt.";
  if (row.status === "no permissions") return "Check the host's Android udev rules and reconnect USB.";
  if (row.status === "offline") return "Reconnect the cable or wireless endpoint, then refresh.";
  if (row.pair) return "Open Wireless debugging → Pair device with pairing code on Android.";
  if (row.source === "mdns") return "Choose Connect. If authentication fails, DroidLink opens Pair with this host.";
  if (row.status !== "device") return "Mirroring requires an authorized device in normal Android mode.";
  return "";
}

function commandError(code, output, error, name) {
  if (code === 124 || code === 137) return name + " timed out. Try again.";
  if (code === 127) return name + " is unavailable. Install the required executable and refresh.";
  return String(error || output || name + " exited with code " + code).trim().slice(-1800);
}

/** Summarize discover-mdns.sh stderr for the Devices page.
 * A cached record whose host no longer answers yields Avahi resolve timeouts, once per
 * IPv4/IPv6 record; those become one hint per device. Unknown lines stay in details.
 * Example: mdnsStatus(0, "Failed to resolve service 'adb-X-a' of type '_adb-tls-connect._tcp' in domain 'local': Timeout reached", [], {})
 *   → { level: "warning", text: "X was seen but didn't answer. Wake it and check Wireless debugging is on.", details: "…" }
 * @param {number} code @param {string} error @param {Array<object>} services parsed rows from this scan
 * @param {object} knownNames service name → device model, from earlier scans
 * @returns {{level: string, text: string, details: string}} level is "", "warning" or "error" */
function mdnsStatus(code, error, services, knownNames) {
  var lines = String(error || "").split(/\r?\n/).map(function(line) { return line.trim(); })
    .filter(function(line, index, all) { return line && all.indexOf(line) === index; });
  var details = lines.join("\n");
  if (code === 124 || code === 137 || code === 127)
    return { level: "error", text: commandError(code, "", error, "Wireless discovery"), details: details };
  var missing = lines.filter(function(line) { return /^DroidLink mDNS: missing /.test(line); })[0];
  if (missing) return { level: "error", text: missing.replace(/^DroidLink mDNS: /, ""), details: details };
  var failedTypes = lines.filter(function(line) { return /^DroidLink mDNS: \S+ discovery failed/.test(line); }).length;
  if (failedTypes >= 3 || lines.some(function(line) { return /Daemon not running/.test(line); }))
    return { level: "error", text: "Avahi isn't responding. Check that avahi-daemon is running.", details: details };

  var answered = (Array.isArray(services) ? services : []).map(function(row) { return row.serial; });
  var silent = [], incomplete = false;
  lines.forEach(function(line) {
    var resolve = /^Failed to resolve service '(.+)' of type '[^']+' in domain '[^']*': Timeout reached$/.exec(line);
    if (resolve) {
      var name = resolve[1];
      if (answered.indexOf(name) < 0 && silent.indexOf(name) < 0) silent.push(name);
    } else incomplete = true;
  });
  var hints = silent.map(function(name) {
    var label = (knownNames && knownNames[name]) || (/^adb-(.+)-[^-]+$/.exec(name) || [])[1] || name;
    return label + " was seen but didn't answer. Wake it and check Wireless debugging is on.";
  });
  if (incomplete) hints.push("Part of wireless discovery didn't finish, so some devices may be missing.");
  return { level: hints.length ? "warning" : "", text: hints.join("\n"), details: details };
}

function adbCommand(action, target) {
  var address = endpoint(target);
  if (action === "disconnect" && !address && /^[a-zA-Z0-9][a-zA-Z0-9_-]*\._adb(?:-tls-connect)?\._tcp(?:\.(?:local\.?)?)?$/.test(target)) address = target;
  if (["connect", "disconnect", "pair"].indexOf(action) < 0 || !address) throw new Error("Enter a valid host:port (IPv6: [address]:port).");
  return ["adb", action, address];
}

function actionSucceeded(action, code, output, error) {
  if (code !== 0 || /failed|cannot|unable|error:|refused/i.test(output + "\n" + error)) return false;
  return ({ connect: /(?:already )?connected to /i, pair: /successfully paired to /i, disconnect: /disconnected /i })[action].test(output);
}

function builtInProfiles() {
  return [
    { name: "Balanced", maxSize: "1920", fps: "60", codec: "h264", bitrate: "8", audio: true, record: false, screenOff: false, fullscreen: false },
    { name: "Low bandwidth", maxSize: "720", fps: "30", codec: "h264", bitrate: "4", audio: false, record: false, screenOff: false, fullscreen: false },
    { name: "High quality", maxSize: "0", fps: "60", codec: "h265", bitrate: "20", audio: true, record: false, screenOff: false, fullscreen: false }
  ];
}

function validProfile(p) {
  return p && typeof p.name === "string" && p.name.trim().length > 0 && p.name.length <= 48 &&
    ["0", "720", "1080", "1440", "1920", "2560", "3840"].indexOf(String(p.maxSize)) >= 0 &&
    ["0", "15", "24", "30", "60", "90", "120"].indexOf(String(p.fps)) >= 0 &&
    ["h264", "h265", "av1"].indexOf(p.codec) >= 0 &&
    ["2", "4", "8", "12", "16", "20", "32", "50", "60"].indexOf(String(p.bitrate)) >= 0 &&
    ["audio", "record", "screenOff", "fullscreen"].every(function(key) { return typeof p[key] === "boolean"; }) &&
    (p.keepActive === undefined || typeof p.keepActive === "boolean");
}

/** Resolve legacy profiles without discarding saved options. Example: preventsIdleSleep({screenOff: true}).
 * @param {{screenOff: boolean, keepActive?: boolean}} profile
 * @returns {boolean}
 */
function preventsIdleSleep(profile) {
  if (typeof profile.keepActive === "boolean") return profile.keepActive;
  // scrcpy v4.1 doc/device.md: inactivity sleep is separate from display power.
  return profile.screenOff;
}

function savedProfiles(json) {
  try {
    var parsed = JSON.parse(json), names = ["Custom"].concat(builtInProfiles().map(function(p) { return p.name; }));
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(function(p) {
      if (!validProfile(p) || names.indexOf(p.name) >= 0) return false;
      names.push(p.name);
      return true;
    }).slice(0, 30);
  } catch (_) { return []; }
}

function scrcpyCommand(serial, profile, recordPath) {
  if (!serial || /[\x00-\x1f\x7f]/.test(serial)) throw new Error("Select an authorized Android device.");
  if (!validProfile(profile)) throw new Error("Select valid mirroring options.");
  var args = ["scrcpy", "--serial=" + serial, "--video-codec=" + profile.codec, "--video-bit-rate=" + profile.bitrate + "M"];
  if (String(profile.maxSize) !== "0") args.push("--max-size=" + profile.maxSize);
  if (String(profile.fps) !== "0") args.push("--max-fps=" + profile.fps);
  if (!profile.audio) args.push("--no-audio");
  if (profile.screenOff) args.push("--turn-screen-off");
  if (preventsIdleSleep(profile)) args.push("--keep-active");
  if (profile.fullscreen) args.push("--fullscreen");
  if (profile.record) {
    if (!recordPath || recordPath[0] !== "/" || /[\x00-\x1f\x7f]/.test(recordPath) || !/\.mkv$/i.test(recordPath)) throw new Error("Choose an absolute recording folder.");
    args.push("--record=" + recordPath);
  }
  return args;
}

function audioOnlyCommand(serial, profile, recordPath) {
  if (!serial || /[\x00-\x1f\x7f]/.test(serial)) throw new Error("Select an authorized Android device.");
  if (!validProfile(profile)) throw new Error("Select valid mirroring options.");
  // --no-video alone can still create scrcpy's control window.
  var args = ["scrcpy", "--serial=" + serial, "--no-video", "--no-window"];
  if (profile.record) {
    if (!recordPath || recordPath[0] !== "/" || /[\x00-\x1f\x7f]/.test(recordPath) || !/\.mka$/i.test(recordPath)) throw new Error("Choose an absolute recording folder.");
    args.push("--record=" + recordPath, "--record-format=mka");
  }
  return args;
}

function recordingPath(folder, serial, now, nonce, extension) {
  folder = String(folder || "").trim().replace(/\/+$/, "");
  if (!folder || folder[0] !== "/" || /[\x00-\x1f\x7f]/.test(folder)) throw new Error("Enter an existing absolute recording folder.");
  extension = String(extension || "mkv").replace(/^\./, "").toLowerCase();
  if (["mkv", "mka"].indexOf(extension) < 0) throw new Error("Choose a supported recording format.");
  return folder + "/DroidLink-" + String(serial).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 48) + "-" + now.toISOString().replace(/[:.]/g, "-") + "-" + nonce + "." + extension;
}
