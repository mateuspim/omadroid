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

/** Split `adb track-devices -l` output into device lists. Each frame is a
 * 4-hex-digit byte length followed by that many bytes of `adb devices -l`
 * rows; "0000" is an empty list. An incomplete frame stays in `rest`.
 * Example: takeTrackFrames("0004a b\n00") → { payloads: ["a b\n"], rest: "00" }
 * @param {string} buffer @returns {{payloads: string[], rest: string}} */
function takeTrackFrames(buffer) {
  var payloads = [], text = String(buffer);
  while (text.length >= 4) {
    if (!/^[0-9a-fA-F]{4}/.test(text))
      throw new Error("Unexpected adb track-devices output " + JSON.stringify(text.slice(0, 32)) + "; expected a 4-digit hex length.");
    var end = utf8End(text, 4, parseInt(text.slice(0, 4), 16));
    if (end < 0) break;
    payloads.push(text.slice(4, end));
    text = text.slice(end);
  }
  return { payloads: payloads, rest: text };
}

// The frame length counts bytes; the decoded text counts UTF-16 units.
function utf8End(text, start, bytes) {
  var i = start;
  while (bytes > 0) {
    if (i >= text.length) return -1;
    var code = text.codePointAt(i);
    bytes -= code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
    i += code >= 0x10000 ? 2 : 1;
  }
  return i;
}

/** Apply one streamed `avahi-browse --parsable` line to the resolved records,
 * keyed by interface;protocol;name;type;domain. "=" adds or updates, "-"
 * removes, anything else ("+" is unresolved) is ignored.
 * Example: applyMdnsLine(records, "-;eno1;IPv4;adb-X;_adb-tls-connect._tcp;local") → true if it was known
 * @param {Object<string, string>} records mutated in place @param {string} line
 * @returns {boolean} whether the records changed */
function applyMdnsLine(records, line) {
  var fields = String(line).split(";");
  if (fields.length < 6) return false;
  var key = fields.slice(1, 6).join(";");
  if (fields[0] === "=" && fields.length >= 9) {
    if (records[key] === line) return false;
    records[key] = line;
    return true;
  }
  if (fields[0] !== "-" || !(key in records)) return false;
  delete records[key];
  return true;
}

/** True when two plain values (parsed rows, maps) hold the same data, so a
 * rescan that found nothing new doesn't rebuild every bound view.
 * Example: sameData([{ a: 1 }], [{ a: 1 }]) → true */
function sameData(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
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
    // One row per service: a device announced over IPv4 and IPv6 (or on two
    // interfaces) is one device. IPv4 wins; link-local IPv6 needs a scope.
    var ipv6 = fields[2] === "IPv6";
    var id = type + ";" + name;
    if (id in seen && (ipv6 || !seen[id].ipv6)) return rows;
    var pair = type === "_adb-tls-pairing._tcp";
    // TXT is the rest of the line: "api=36.1" "name=SM-X730" "v=1".
    var model = (/"name=([^"]*)"/.exec(fields.slice(9).join(";")) || [])[1] || "";
    var row = { key: "mdns:" + type + ":" + address, name: serviceId(name), serial: name, model: model, status: pair ? "pairing" : "discovered",
      transport: "Wireless", endpoint: address, service: type, source: "mdns", pair: pair };
    if (id in seen) rows[seen[id].index] = row;
    else seen[id] = { index: rows.push(row) - 1 };
    seen[id].ipv6 = ipv6;
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

/** One-line card summary. Example: "Battery 71 % · Android 16 · 136/239 GB used" */
function deviceSummary(info) {
  if (!info) return "";
  var parts = [];
  if (info.battery && info.battery.level !== undefined)
    parts.push("Battery " + info.battery.level + " %" + (info.battery.status === 2 ? " (charging)" : ""));
  if (info.android) parts.push("Android " + info.android);
  if (info.internal) {
    var used = formatSize(info.internal.usedKb), total = formatSize(info.internal.totalKb);
    parts.push((used.split(" ")[1] === total.split(" ")[1] ? used.split(" ")[0] : used) + "/" + total + " used");
  }
  return parts.join(" · ");
}

/** Label/value pairs for the expanded device card, omitting anything unread. */
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

/** Merge adb devices with mDNS services into the Devices page rows.
 * Android runs one wireless adbd per host, so a connect service on the host of
 * a wireless device is that device even when the ports differ: a ready device
 * keeps adb's live endpoint (Avahi may hold a stale cached port), an offline
 * one takes the advertised port so Connect reaches it. adb keeps endpoints it
 * lost as "offline"; once their host is ready on another port they are hidden.
 * Example: deviceRows(parseDevices("10.0.0.2:40001 device"), parseMdns("=;eno1;IPv4;adb-X-y;_adb-tls-connect._tcp;local;a.local;10.0.0.2;39999;"))
 *   → one row, endpoint "10.0.0.2:40001" */
function deviceRows(devices, services) {
  var host = function(row) { return endpointParts(row.endpoint).host; };
  var wireless = function(row) { return row.source === "adb" && row.transport === "Wireless"; };
  var readyHosts = devices.filter(function(row) { return wireless(row) && row.status === "device" && host(row); }).map(host);
  var rows = devices.filter(function(row) {
    return !(wireless(row) && row.status !== "device" && readyHosts.indexOf(host(row)) >= 0);
  }).map(function(row) { return Object.assign({}, row); });
  services.forEach(function(service) {
    var candidates = service.pair ? [] : rows.filter(wireless);
    var existing = candidates.find(function(row) {
      return (row.endpoint && row.endpoint === service.endpoint) || serviceId(row.serial) === serviceId(service.serial);
    }) || candidates.find(function(row) { return host(row) && host(row) === host(service); });
    if (existing) {
      if (existing.status !== "device" || !existing.endpoint) existing.endpoint = service.endpoint;
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
  if (row.source === "mdns") return "Choose Connect. If authentication fails, OmaDroid opens Pair with this host.";
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
  // "Got SIGTERM, quitting." is Avahi's note when OmaDroid stops a browser.
  var lines = String(error || "").split(/\r?\n/).map(function(line) { return line.trim(); })
    .filter(function(line, index, all) { return line && all.indexOf(line) === index && !/^Got SIG[A-Z]+, quitting\.$/.test(line); });
  var details = lines.join("\n");
  if (code === 124 || code === 137 || code === 127)
    return { level: "error", text: commandError(code, "", error, "Wireless discovery"), details: details };
  var missing = lines.filter(function(line) { return /^OmaDroid mDNS: missing /.test(line); })[0];
  if (missing) return { level: "error", text: missing.replace(/^OmaDroid mDNS: /, ""), details: details };
  // The streaming helper stops as a whole when any browser exits.
  if (lines.some(function(line) { return /^OmaDroid mDNS: discovery stopped/.test(line) || /Daemon not running/.test(line); }))
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

/** Parse `scrcpy --list-camera-sizes`. Example line pair:
 * "--camera-id=1    (front, 2032x1524, fps={10, 15, 30}, zoom-range=[1, 8])" then "- 1920x1080"
 * → [{ id: "1", facing: "front", sensor: "2032x1524", fps: [10, 15, 30], zoom: [1, 8], sizes: ["1920x1080"] }].
 * High-speed sizes are left out; OmaDroid does not use high-speed capture.
 */
function parseCameraList(output) {
  var cameras = [], current = null, highSpeed = false;
  String(output || "").split("\n").forEach(function(line) {
    var head = /--camera-id=([0-9A-Za-z_.-]+)\s+\(([^)]*)\)/.exec(line);
    if (head) {
      var fields = head[2], fps = /fps=[{\[]([^}\]]*)[}\]]/.exec(fields), zoom = /zoom-range=\[([^\]]*)\]/.exec(fields);
      var sensor = /(\d+x\d+)/.exec(fields);
      current = {
        id: head[1],
        facing: (/^\s*(front|back|external)/.exec(fields) || [, "external"])[1],
        sensor: sensor ? sensor[1] : "",
        fps: fps ? fps[1].split(",").map(Number).filter(function(n) { return n > 0; }) : [],
        zoom: zoom ? zoom[1].split(",").map(Number) : null,
        sizes: []
      };
      highSpeed = false;
      cameras.push(current);
      return;
    }
    if (!current) return;
    if (/high.speed/i.test(line)) { highSpeed = true; return; }
    var size = /^\s*-\s*(\d+x\d+)\s*$/.exec(line);
    if (size && !highSpeed && current.sizes.indexOf(size[1]) < 0) current.sizes.push(size[1]);
  });
  return cameras;
}

/** Example: cameraLabel({ id: "2", facing: "front", sensor: "4000x3000" }) → "Front · 4000×3000 · camera 2" */
function cameraLabel(camera) {
  var facing = camera.facing.charAt(0).toUpperCase() + camera.facing.slice(1);
  return [facing, camera.sensor.replace("x", "×"), "camera " + camera.id].filter(Boolean).join(" · ");
}

/** Camera choices: every listed camera by id, else the two facings. Values are "id:N", "front" or "back". */
function cameraOptions(cameras) {
  if (!cameras || !cameras.length) return [{ value: "front", label: "Front" }, { value: "back", label: "Back" }];
  return cameras.map(function(camera) { return { value: "id:" + camera.id, label: cameraLabel(camera) }; });
}

/** The listed camera a choice names: by id, or the first with that facing (what scrcpy picks). */
function chosenCamera(cameras, choice) {
  if (!cameras) return null;
  var id = /^id:(.+)$/.exec(choice || "");
  return cameras.find(function(camera) { return id ? camera.id === id[1] : camera.facing === choice; }) || null;
}

var sizeNames = { "3840x2160": "4K", "2560x1440": "1440p", "1920x1080": "1080p", "1280x720": "720p" };

/** Example: sizeLabel("3840x2160") → "3840×2160 · 16:9 · 4K" */
function sizeLabel(size) {
  var parts = size.split("x").map(Number);
  return [size.replace("x", "×"), aspectRatio(parts[0], parts[1]), sizeNames[size] || ""].filter(Boolean).join(" · ");
}

/** Sizes worth offering for a webcam, largest first: the camera's list from
 * 640 px wide up, else common sizes when the camera is unknown. */
function cameraSizeOptions(camera) {
  var sizes = camera && camera.sizes.length ? camera.sizes : ["1920x1080", "1280x720", "640x480"];
  sizes = sizes.filter(function(size) { return Number(size.split("x")[0]) >= 640; }).sort(function(a, b) {
    var pa = a.split("x").map(Number), pb = b.split("x").map(Number);
    return pb[0] * pb[1] - pa[0] * pa[1] || pb[0] - pa[0];
  });
  return [{ value: "auto", label: "Automatic · camera default" }].concat(sizes.map(function(size) { return { value: size, label: sizeLabel(size) }; }));
}

/** Frame rates the camera lists (Android's default is 30), else 15, 24 and 30. */
function cameraFpsOptions(camera) {
  var rates = camera && camera.fps.length ? camera.fps.filter(function(n) { return n >= 10; }) : [15, 24, 30];
  // A camera listing only slow rates still offers them.
  if (!rates.length) rates = camera.fps.slice();
  return rates.slice().sort(function(a, b) { return b - a; }).map(function(n) { return { value: String(n), label: n + " fps" }; });
}

/** Initial zoom steps within the camera's range; 1× when the range is unknown. */
function cameraZoomOptions(camera) {
  var range = camera && camera.zoom && camera.zoom.length === 2 ? camera.zoom : [1, 1];
  return [1, 1.5, 2, 3, 4, 6, 8, 10].filter(function(z) { return z >= range[0] && z <= range[1]; }).map(function(z) {
    return { value: String(z), label: z + "×" };
  });
}

/** Quality presets: a target size (the closest the camera supports is used), fps, Mbps and codec. */
function webcamPresets() {
  return [
    { value: "call", label: "Call · 1080p · 30 fps · 12 Mbps", size: "1920x1080", fps: "30", bitRate: "12", codec: "h265" },
    { value: "sharp", label: "Sharp · 4K · 30 fps · 24 Mbps", size: "3840x2160", fps: "30", bitRate: "24", codec: "h265" },
    { value: "saver", label: "Saver · 720p · 24 fps · 6 Mbps", size: "1280x720", fps: "24", bitRate: "6", codec: "h264" }
  ];
}

/** The target size if the camera lists it, else its largest size of the same
 * aspect no larger than the target, else "auto". Unknown cameras get the target. */
function pickCameraSize(camera, target) {
  if (!camera || !camera.sizes.length) return target;
  if (camera.sizes.indexOf(target) >= 0) return target;
  var t = target.split("x").map(Number), want = aspectRatio(t[0], t[1]);
  var fits = camera.sizes.filter(function(size) {
    var p = size.split("x").map(Number);
    return p[0] <= t[0] && p[1] <= t[1] && aspectRatio(p[0], p[1]) === want;
  });
  // Not cameraSizeOptions: with nothing left it offers generic sizes.
  fits.sort(function(a, b) { return Number(b.split("x")[0]) * Number(b.split("x")[1]) - Number(a.split("x")[0]) * Number(a.split("x")[1]); });
  return fits.length ? fits[0] : "auto";
}

/** The highest listed rate no faster than `target`, else the camera's slowest. */
function pickCameraFps(camera, target) {
  var rates = cameraFpsOptions(camera).map(function(o) { return Number(o.value); });
  if (!rates.length) rates = camera.fps.slice().sort(function(a, b) { return b - a; });
  var fit = rates.find(function(n) { return n <= Number(target); });
  return String(fit || rates[rates.length - 1] || target);
}

/** Example: webcamSummary({ size: "1920x1080", fps: "30", bitRate: "12", codec: "h265", orientation: "flip0", zoom: "2", torch: true, buffer: "0" })
 * → "1080p · 30 fps · 12 Mbps · H.265 · Mirror · 2× · Torch" */
function webcamSummary(o) {
  var size = o.size === "auto" ? "Auto size" : sizeNames[o.size] || o.size.replace("x", "×");
  var turn = { "0": "", "90": "90°", "180": "180°", "270": "270°", flip0: "Mirror", flip90: "Mirror 90°", flip180: "Mirror 180°", flip270: "Mirror 270°" }[o.orientation] || "";
  return [size, o.fps + " fps", o.bitRate + " Mbps", o.codec === "h265" ? "H.265" : o.codec === "h264" ? "H.264" : o.codec.toUpperCase(), turn,
    Number(o.zoom) !== 1 ? o.zoom + "×" : "", o.torch ? "Torch" : "", o.buffer !== "0" ? o.buffer + " ms" : ""].filter(Boolean).join(" · ");
}

var webcamDefaults = { camera: "front", orientation: "0", preset: "call", size: "1920x1080", fps: "30", bitRate: "12", codec: "h265", zoom: "1", torch: false, buffer: "0" };

/** Saved webcam settings over the defaults; unknown keys and bad JSON are dropped. */
function webcamSettings(json) {
  var saved = {};
  try { saved = JSON.parse(json || "{}") || {}; } catch (e) { saved = {}; }
  var out = {};
  Object.keys(webcamDefaults).forEach(function(key) {
    out[key] = saved[key] !== undefined && typeof saved[key] === typeof webcamDefaults[key] ? saved[key] : webcamDefaults[key];
  });
  return out;
}

/** Build a camera sink command from webcamSettings-shaped options.
 * Example: webcamCommand('USB', { camera: 'id:2', orientation: '0', size: '1920x1080', fps: '30', bitRate: '12', codec: 'h265', zoom: '1', torch: false, buffer: '0' }, '/dev/video10')
 */
function webcamCommand(serial, options, sink) {
  var o = options || {};
  if (!serial || /[\x00-\x1f\x7f]/.test(serial)) throw new Error("Select a ready Android device.");
  var id = /^id:([0-9A-Za-z_.-]+)$/.exec(o.camera || "");
  if (!id && ["front", "back", "external"].indexOf(o.camera) < 0) throw new Error("Invalid camera '" + o.camera + "'; choose a listed camera.");
  if (["0", "90", "180", "270", "flip0", "flip90", "flip180", "flip270"].indexOf(String(o.orientation)) < 0)
    throw new Error("Invalid camera orientation '" + o.orientation + "'; choose a listed rotation.");
  if (o.size !== "auto" && !/^[1-9][0-9]{1,4}x[1-9][0-9]{1,4}$/.test(o.size || ""))
    throw new Error("Invalid camera size '" + o.size + "'; choose a listed resolution.");
  if (!/^[1-9][0-9]{0,2}$/.test(o.fps || "")) throw new Error("Invalid frame rate '" + o.fps + "'; choose a listed rate.");
  if (!/^[1-9][0-9]?$/.test(o.bitRate || "")) throw new Error("Invalid bitrate '" + o.bitRate + "'; choose 1 to 99 Mbps.");
  if (["h264", "h265", "av1"].indexOf(o.codec) < 0) throw new Error("Invalid codec '" + o.codec + "'; choose H.264, H.265 or AV1.");
  if (!/^[0-9]+(\.[0-9]+)?$/.test(o.zoom || "") || Number(o.zoom) <= 0) throw new Error("Invalid zoom '" + o.zoom + "'.");
  if (!/^[0-9]{1,4}$/.test(o.buffer || "")) throw new Error("Invalid buffer '" + o.buffer + "'; choose a listed delay.");
  if (!/^\/dev\/video[0-9]+$/.test(sink)) throw new Error("Invalid webcam output '" + sink + "'; choose a listed /dev/videoN device.");
  // scrcpy refuses --camera-facing together with --camera-id.
  var args = ["scrcpy", "--serial=" + serial, "--video-source=camera", id ? "--camera-id=" + id[1] : "--camera-facing=" + o.camera,
    "--capture-orientation=" + o.orientation, "--no-audio", "--no-window", "--v4l2-sink=" + sink,
    "--camera-fps=" + o.fps, "--video-bit-rate=" + o.bitRate + "M", "--video-codec=" + o.codec];
  if (o.size !== "auto") args.push("--camera-size=" + o.size);
  if (Number(o.zoom) !== 1) args.push("--camera-zoom=" + o.zoom);
  if (o.torch === true) args.push("--camera-torch");
  if (o.buffer !== "0") args.push("--v4l2-buffer=" + o.buffer);
  return args;
}

/** Describe the next webcam setup step. Example: webcamSetup('missing-package'). */
function webcamSetup(issue) {
  var load = "sudo modprobe v4l2loopback devices=1 exclusive_caps=1\n"
    + "printf 'v4l2loopback\\n' | sudo tee /etc/modules-load.d/v4l2loopback.conf\n"
    + "printf 'options v4l2loopback devices=1 exclusive_caps=1\\n' | sudo tee /etc/modprobe.d/v4l2loopback.conf";
  switch (issue) {
  case "missing-package": return { title: "Virtual camera driver missing", detail: "Install the driver and enable one output, now and at every boot.", action: "Set up webcam", step: "install", commands: "omarchy pkg add v4l2loopback-dkms\n" + load };
  case "module-not-loaded": return { title: "Virtual camera is off", detail: "The driver is installed. Enable one output, now and at every boot, to use your phone as a camera.", action: "Enable output", step: "load", commands: load };
  case "module-unavailable": return { title: "Driver needs a build", detail: "The package is installed, but no module is available for this kernel. Check the DKMS build and matching kernel headers.", action: "", step: "", commands: "dkms status\npacman -Q linux-omarchy-headers v4l2loopback-dkms" };
  case "no-output": return { title: "No virtual camera output", detail: "The driver is loaded, but no output is visible. Check its devices and permissions.", action: "", step: "", commands: "ls -l /dev/video*" };
  case "scan-error": return { title: "Could not check camera outputs", detail: "Press Refresh to try again.", action: "", step: "", commands: "" };
  default: return { title: "No virtual camera output", detail: "Enable a v4l2loopback output, then press Refresh.", action: "", step: "", commands: "" };
  }
}

function recordingPath(folder, serial, now, nonce, extension) {
  folder = String(folder || "").trim().replace(/\/+$/, "");
  if (!folder || folder[0] !== "/" || /[\x00-\x1f\x7f]/.test(folder)) throw new Error("Enter an existing absolute recording folder.");
  extension = String(extension || "mkv").replace(/^\./, "").toLowerCase();
  if (["mkv", "mka"].indexOf(extension) < 0) throw new Error("Choose a supported recording format.");
  return folder + "/OmaDroid-" + String(serial).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 48) + "-" + now.toISOString().replace(/[:.]/g, "-") + "-" + nonce + "." + extension;
}
