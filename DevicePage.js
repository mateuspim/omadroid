.import "Model.js" as Model

// Text for the device page's hero and Info section, from a discovery row and
// its parsed device-info.sh `info`.

/** The page's sections, in switcher order. Sessions (Mirror, Audio, Webcam)
 * are cards above the switcher, not sections. */
function deviceSections() {
  return [
    { value: "sound", label: "Sound" },
    { value: "info", label: "Info" }
  ];
}

/** A known section, or "sound" for anything else, such as the "mirror" and
 * "webcam" sections a panel remembered before they became cards.
 * Example: pageSection("info") → "info"; pageSection("mirror") → "sound" */
function pageSection(value) {
  return deviceSections().some(function(s) { return s.value === value; }) ? value : "sound";
}

/** Hero meta line: model (when it isn't the name) · Android · transport, and
 * the status when the device isn't ready.
 * Example: heroMeta({ name: "Desk phone", model: "Pixel 6", transport: "USB", status: "device", info: { android: "16" } })
 *   → "Pixel 6 · Android 16 · USB" */
function heroMeta(row) {
  var parts = [];
  if (row.model && row.model !== row.name) parts.push(row.model);
  if (row.info && row.info.android) parts.push("Android " + row.info.android);
  parts.push(row.transport);
  if (row.status !== "device") parts.push(Model.statusLabel(row.status));
  return parts.join(" · ");
}

/** Hero stats line: battery (⚡ while charging), internal storage, memory.
 * Example: heroStats({ battery: { level: 64, status: 2 }, internal: { usedKb: 132812500, totalKb: 233398437 }, memKb: 7812500 })
 *   → "64% ⚡ · 136/239 GB · 8 GB RAM" */
function heroStats(info) {
  if (!info) return "";
  var parts = [];
  if (info.battery && info.battery.level !== undefined)
    parts.push(info.battery.level + "%" + (info.battery.status === 2 ? " ⚡" : ""));
  if (info.internal) parts.push(storageShort(info.internal));
  if (info.memKb) parts.push(Model.formatSize(info.memKb) + " RAM");
  return parts.join(" · ");
}

/** "136/239 GB", or "125 GB/1.02 TB" when the units differ. */
function storageShort(storage) {
  var used = Model.formatSize(storage.usedKb), total = Model.formatSize(storage.totalKb);
  var sameUnit = used.split(" ")[1] === total.split(" ")[1];
  return (sameUnit ? used.split(" ")[0] : used) + "/" + total;
}

/** Copyable identity rows for the Info section: the adb serial (or mDNS
 * service name) and the endpoint when it differs.
 * Example: identityRows({ serial: "10.0.0.2:5555", endpoint: "10.0.0.2:5555", source: "adb" })
 *   → [{ label: "Serial", value: "10.0.0.2:5555" }] */
function identityRows(row) {
  var rows = [{ label: row.source === "mdns" ? "Service" : "Serial", value: row.serial }];
  if (row.endpoint && row.endpoint !== row.serial) rows.push({ label: "Address", value: row.endpoint });
  return rows;
}
