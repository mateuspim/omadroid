.import "Model.js" as Model
// Auto-connect projections: shared by QML and the Node fixture tests.

var CONNECT_SERVICE = "_adb-tls-connect._tcp";

/** The device behind a Wireless debugging service. adbd names it
 * "adb-<ro.serialno>-<suffix>"; the suffix is dropped in case it changes.
 * Example: deviceKey("adb-R5CR123ABC-a1B2c3") → "adb-R5CR123ABC" */
function deviceKey(serviceName) {
  var match = /^(adb-.+)-[^-]+$/.exec(String(serviceName || ""));
  return match ? match[1] : String(serviceName || "");
}

// A ready wireless adb transport for this connect service: any host it
// announced (a link made over IPv6 before the IPv4 record resolved counts),
// or the service name itself when adb connected through mDNS.
function readyFor(service, devices) {
  return devices.some(function(row) {
    return row.status === "device" && row.transport === "Wireless" &&
      (Model.announcesHost(service, Model.endpointParts(row.endpoint).host) || Model.serviceId(row.serial) === Model.serviceId(service.serial));
  });
}

function connectServices(services) {
  return (Array.isArray(services) ? services : []).filter(function(row) {
    return row.service === CONNECT_SERVICE && !row.pair && row.endpoint;
  });
}

/** Keys of devices ready over Wi-Fi right now: they trust this computer.
 * Example: trustedKeys([{ serial: "10.0.0.2:40001", status: "device", transport: "Wireless", endpoint: "10.0.0.2:40001" }],
 *   [{ serial: "adb-R5CR-x", service: "_adb-tls-connect._tcp", endpoint: "10.0.0.2:40001" }]) → ["adb-R5CR"]
 * @param {Array<object>} devices parsed adb rows @param {Array<object>} services parsed mDNS rows @returns {string[]} */
function trustedKeys(devices, services) {
  return connectServices(services).filter(function(service) {
    return readyFor(service, Array.isArray(devices) ? devices : []);
  }).map(function(service) { return deviceKey(service.serial); });
}

/** Endpoints to connect: announced by a known device that isn't ready, and not
 * tried since they appeared. A refused endpoint isn't retried; toggling
 * Wireless debugging announces a new port, which is tried once.
 * Example: autoConnectTargets([], [{ serial: "adb-R5CR-x", service: "_adb-tls-connect._tcp", endpoint: "10.0.0.2:40001" }], ["adb-R5CR"], {})
 *   → ["10.0.0.2:40001"]
 * @param {Array<object>} devices @param {Array<object>} services @param {string[]} known device keys
 * @param {Object<string, boolean>} tried endpoints already tried @returns {string[]} */
function autoConnectTargets(devices, services, known, tried) {
  return connectServices(services).filter(function(service) {
    return known.indexOf(deviceKey(service.serial)) >= 0 && !(tried && tried[service.endpoint]) &&
      !readyFor(service, Array.isArray(devices) ? devices : []);
  }).map(function(service) { return service.endpoint; });
}

/** Tried endpoints still announced; one that left and returns is tried again.
 * Example: stillAnnounced({ "10.0.0.2:40001": true, "10.0.0.9:1": true }, services) → { "10.0.0.2:40001": true } */
function stillAnnounced(tried, services) {
  var kept = {};
  connectServices(services).forEach(function(service) {
    if (tried && tried[service.endpoint]) kept[service.endpoint] = true;
  });
  return kept;
}

/** The device key announced at an endpoint, "" when none is.
 * Example: keyAt(services, "10.0.0.2:40001") → "adb-R5CR" */
function keyAt(services, endpoint) {
  var match = connectServices(services).find(function(service) { return service.endpoint === endpoint; });
  return match ? deviceKey(match.serial) : "";
}

/** Merge keys into the remembered list, oldest first, keeping at most 50.
 * Example: rememberKeys(["a"], ["b", "a"]) → ["a", "b"] */
function rememberKeys(known, keys) {
  var merged = (Array.isArray(known) ? known : []).slice();
  keys.forEach(function(key) {
    if (key && merged.indexOf(key) < 0) merged.push(key);
  });
  return merged.slice(-50);
}

/** Parse the remembered keys setting; anything unexpected is an empty list.
 * Example: parseKeys('["adb-R5CR"]') → ["adb-R5CR"] */
function parseKeys(json) {
  try {
    var keys = JSON.parse(json);
    return Array.isArray(keys) ? keys.filter(function(key) { return typeof key === "string" && /^adb-[!-~]{1,128}$/.test(key); }) : [];
  } catch (_) {
    return [];
  }
}

/** True when adb says this computer isn't trusted, as opposed to a network failure.
 * Example: refusedTrust("failed to authenticate to 10.0.0.2:40001") → true */
function refusedTrust(output) {
  return /authenticat|unauthorized/i.test(String(output || ""));
}
