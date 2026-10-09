// QR pairing projections: shared by QML and the Node fixture tests.

/** Parse qr-pair.sh output into the pairing service name, its password and the
 * QR modules as one "0"/"1" string, row by row.
 * Example: parseQrPairing("service\tdroidlink-abcd2345\npassword\tabcdefgh23456789\nrow\t10\nrow\t01\n")
 *   → { service: "droidlink-abcd2345", password: "abcdefgh23456789", size: 2, cells: "1001" }
 * @param {string} output @returns {{service: string, password: string, size: number, cells: string}} */
function parseQrPairing(output) {
  var result = { service: "", password: "", size: 0, cells: "" }, rows = [];
  String(output).split(/\r?\n/).forEach(function(line) {
    var fields = line.split("\t");
    if (fields.length !== 2) return;
    if (fields[0] === "service" && /^droidlink-[a-z2-9]{8}$/.test(fields[1])) result.service = fields[1];
    else if (fields[0] === "password" && validQrPassword(fields[1])) result.password = fields[1];
    else if (fields[0] === "row" && /^[01]+$/.test(fields[1])) rows.push(fields[1]);
  });
  var square = rows.length > 0 && rows.every(function(row) { return row.length === rows.length; });
  if (!result.service || !result.password || !square)
    throw new Error("Unexpected qr-pair.sh output " + JSON.stringify(String(output).slice(0, 80)) + "; expected service, password and square 0/1 rows.");
  result.size = rows.length;
  result.cells = rows.join("");
  return result;
}

function validQrPassword(value) {
  return /^[a-z2-9]{16}$/.test(String(value));
}

/** True for a secret `adb pair` may receive: Android's six-digit code, or a
 * password DroidLink put in a QR code.
 * Example: validPairingSecret("123456") → true; validPairingSecret("12345") → false */
function validPairingSecret(value) {
  return /^\d{6}$/.test(String(value || "")) || validQrPassword(value);
}

/** The pairing endpoint Android announced for a scanned QR code: the
 * `_adb-tls-pairing._tcp` service named after the code. Other devices' pairing
 * services never match, so a code only pairs the phone that scanned it.
 * Example: qrPairingEndpoint([{ pair: true, serial: "droidlink-abcd2345", endpoint: "192.168.1.5:42000" }], "droidlink-abcd2345")
 *   → "192.168.1.5:42000"
 * @param {Array<object>} rows discovery rows @param {string} service @returns {string} "" until announced */
function qrPairingEndpoint(rows, service) {
  if (!service) return "";
  var match = (Array.isArray(rows) ? rows : []).find(function(row) {
    return row.pair && row.serial === service && row.endpoint;
  });
  return match ? match.endpoint : "";
}
