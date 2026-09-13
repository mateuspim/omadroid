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
    rows.push({ key: key, name: serviceId(name), serial: name, status: pair ? "pairing" : "discovered",
      transport: "Wireless", endpoint: address, service: type, source: "mdns", pair: pair });
    return rows;
  }, []);
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
  if (row.source === "mdns") return "Connect if this host is paired, or choose Pair… for a new host.";
  if (row.status !== "device") return "Mirroring requires an authorized device in normal Android mode.";
  return "";
}

function commandError(code, output, error, name) {
  if (code === 124 || code === 137) return name + " timed out. Try again.";
  if (code === 127) return name + " is unavailable. Install the required executable and refresh.";
  return String(error || output || name + " exited with code " + code).trim().slice(-1800);
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
    { name: "Balanced", maxSize: "1080", fps: "60", codec: "h264", bitrate: "8", audio: true, record: false, screenOff: false, fullscreen: false },
    { name: "Low bandwidth", maxSize: "720", fps: "30", codec: "h264", bitrate: "4", audio: false, record: false, screenOff: false, fullscreen: false },
    { name: "High quality", maxSize: "0", fps: "60", codec: "h265", bitrate: "20", audio: true, record: false, screenOff: false, fullscreen: false }
  ];
}

function validProfile(p) {
  return p && typeof p.name === "string" && p.name.trim().length > 0 && p.name.length <= 48 &&
    ["0", "720", "1080", "1440", "1920", "2560"].indexOf(String(p.maxSize)) >= 0 &&
    ["0", "15", "24", "30", "60", "90", "120"].indexOf(String(p.fps)) >= 0 &&
    ["h264", "h265", "av1"].indexOf(p.codec) >= 0 &&
    ["2", "4", "8", "12", "16", "20", "32", "50"].indexOf(String(p.bitrate)) >= 0 &&
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
