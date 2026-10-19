// Pure projections: shared by QML and the Node fixture tests. Webcam and
// device-info projections live in Webcam.js and DeviceInfo.js.
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

/** Merge adb devices with mDNS services into the home view's device rows.
 * Android runs one wireless adbd per host, so a connect service on the host of
 * a wireless device is that device even when the ports differ: a ready device
 * keeps adb's live endpoint (Avahi may hold a stale cached port), an offline
 * one takes the advertised port so Connect reaches it. adb keeps endpoints it
 * lost as "offline"; once their host is ready on another port they are hidden.
 * adb can hold two ready links to one device, its own mDNS auto-connect (named
 * after the service) and an `adb connect host:port`; when the service ties
 * them together the host:port row stays and lists the other in `aliases`.
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
    if (service.pair) return;
    var ready = rows.filter(function(row) { return wireless(row) && row.status === "device"; });
    var byEndpoint = ready.find(function(row) { return row.endpoint && row.endpoint === service.endpoint; }) ||
      ready.find(function(row) { return row.endpoint && host(row) === host(service); });
    var byName = ready.find(function(row) { return !row.endpoint && serviceId(row.serial) === serviceId(service.serial); });
    if (!byEndpoint || !byName) return;
    byEndpoint.aliases = (byEndpoint.aliases || []).concat(byName.serial);
    rows.splice(rows.indexOf(byName), 1);
  });
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

/** Summarize discover-mdns.sh stderr for the home view's device list.
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

function recordingPath(folder, serial, now, nonce, extension) {
  folder = String(folder || "").trim().replace(/\/+$/, "");
  if (!folder || folder[0] !== "/" || /[\x00-\x1f\x7f]/.test(folder)) throw new Error("Enter an existing absolute recording folder.");
  extension = String(extension || "mkv").replace(/^\./, "").toLowerCase();
  if (["mkv", "mka"].indexOf(extension) < 0) throw new Error("Choose a supported recording format.");
  return folder + "/OmaDroid-" + String(serial).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 48) + "-" + now.toISOString().replace(/[:.]/g, "-") + "-" + nonce + "." + extension;
}
