// Projections of `device-volume.sh status` for the device page's Sound section.
// tests/device-volume.sh covers device-volume.sh itself.

// Stream key → label, in the order the page lists them.
var streamLabels = {
  media: "Media",
  notification: "Notifications",
  ring: "Ringtone",
  call: "Calls",
  system: "System",
  alarm: "Alarms",
  assistant: "Assistant / Bixby"
};

/** Parse `device-volume.sh status`. Example:
 * parseVolumeStatus("mode samsung\nmaster 0\nringer normal\nstream media 3 13 0 15 0\napp 10360 playing 10 0 com.x Game")
 * → { mode: "samsung", master: false, ringer: "normal", streams: [{ key: "media", index: 3, volume: 13, min: 0, max: 15, muted: false, label: "Media" }],
 *     apps: [{ uid: 10360, playing: true, volume: 10, muted: false, package: "com.x", label: "Game", naming: false }] }
 * A "naming UID" line marks an app whose label is still being read from its APK.
 * @param {string} output
 * @returns {object|null} null without a mode line
 */
function parseVolumeStatus(output) {
  var status = { mode: "", master: null, ringer: "", streams: [], apps: [] };
  var naming = [];
  String(output).split("\n").forEach(function(line) { readStatusLine(status, line.trim(), naming); });
  if (!status.mode)
    return null;
  status.apps.forEach(function(app) { app.naming = naming.indexOf(app.uid) >= 0; });
  status.streams.sort(function(a, b) { return streamOrder(a.key) - streamOrder(b.key); });
  return status;
}

function readStatusLine(status, line, naming) {
  var match;
  if ((match = /^mode (samsung|appops)$/.exec(line)))
    status.mode = match[1];
  else if ((match = /^master ([01-])$/.exec(line)))
    status.master = match[1] === "-" ? null : match[1] === "1";
  else if ((match = /^ringer (normal|vibrate|silent|-)$/.exec(line)))
    status.ringer = match[1] === "-" ? "" : match[1];
  else if ((match = /^stream ([a-z]+) (\d+) (\d+) (\d+) (\d+) ([01])$/.exec(line)) && streamLabels[match[1]])
    status.streams.push({ key: match[1], index: +match[2], volume: +match[3], min: +match[4], max: +match[5], muted: match[6] === "1", label: streamLabels[match[1]] });
  else if ((match = /^app (\d+) (playing|paused) (\d+|-) ([01-]) (\S+) (.+)$/.exec(line)))
    status.apps.push({ uid: +match[1], playing: match[2] === "playing", volume: match[3] === "-" ? null : +match[3], muted: match[4] === "-" ? null : match[4] === "1", package: match[5], label: match[6] });
  else if ((match = /^naming (\d+)$/.exec(line)))
    naming.push(+match[1]);
}

function streamOrder(key) {
  return Object.keys(streamLabels).indexOf(key);
}

/** Apps worth a row: everything playing, plus paused apps that have a
 * name (or one being read) or a changed volume/mute (so a muted app can be
 * restored).
 * Playing first, then by name.
 * Example: visibleApps([{ playing: false, label: "com.x", package: "com.x", volume: 100, muted: false }]) → []
 */
function visibleApps(apps) {
  return apps.filter(function(app) {
    return app.playing || app.naming === true || app.label !== app.package || app.muted === true || (app.volume !== null && app.volume !== 100);
  }).sort(function(a, b) {
    return (b.playing - a.playing) || a.label.localeCompare(b.label);
  });
}

/** Status with one stream or app changed, shown before the next read so a
 * slider doesn't jump back. Example: withChange(status, "app", 10360, { volume: 40 }).
 * @param {object} status @param {string} kind "stream"|"app" @param {string|number} id key or uid
 * @param {object} change fields to replace
 */
function withChange(status, kind, id, change) {
  if (!status)
    return status;
  var copy = JSON.parse(JSON.stringify(status));
  var rows = kind === "stream" ? copy.streams : copy.apps;
  rows.forEach(function(row) {
    if ((kind === "stream" ? row.key : row.uid) !== id)
      return;
    Object.keys(change).forEach(function(name) { row[name] = change[name]; });
  });
  return copy;
}

/** Value text for a row. Example: volumeText(13, 15, false) → "13/15"; volumeText(40, 100, true) → "Muted". */
function volumeText(volume, max, muted) {
  if (muted)
    return "Muted";
  return max === 100 ? volume + "%" : volume + "/" + max;
}

/** Whether a finished status read may be shown. A read for another device
 * (the serial changed while it ran) or one older than a sent change is
 * dropped, so a slider never shows another device's or a stale value.
 * Example: statusReadApplies({ serial: "A", changes: 2 }, { serial: "B", changes: 2, changing: false }) → false
 */
function statusReadApplies(read, current) {
  return read.serial === current.serial && read.changes === current.changes && !current.changing;
}

/** Add a command to the waiting changes. A "set" replaces a waiting "set" of
 * the same stream or app, so a drag sends only its latest value; anything
 * else is appended in order.
 * Example: queueChange([["bash", "v.sh", "app", "S", "1", "set", "35"]], ["bash", "v.sh", "app", "S", "1", "set", "40"])
 *   → [["bash", "v.sh", "app", "S", "1", "set", "40"]]
 * @param {Array<Array<string>>} queue @param {Array<string>} command
 * @returns {Array<Array<string>>} a new queue
 */
function queueChange(queue, command) {
  var target = setTarget(command);
  var kept = target ? queue.filter(function(waiting) { return setTarget(waiting) !== target; }) : queue.slice();
  return kept.concat([command]);
}

// "app S 1" for […, "app", "S", "1", "set", N]; "" for other commands.
function setTarget(command) {
  return command[command.length - 2] === "set" ? command.slice(2, -2).join(" ") : "";
}

/** Make a ListModel's rows equal `keys` (role `rowKey`, strings), in order,
 * by moving, inserting and removing rows, never by replacing the list: a
 * Repeater then keeps the delegates of rows that stay. A rebuilt row's
 * PanelSlider animates its fill from 0, so every renamed or new app made all
 * sliders jump.
 * Example: syncRowKeys(model, ["10360", "10085"]) on rows "10085", "1000"
 *   → rows "10360", "10085" ("10085" keeps its delegate; "1000" is removed)
 * @param {{count: number, get: function, move: function, insert: function, remove: function}} model
 * @param {Array<string>} keys
 */
function syncRowKeys(model, keys) {
  keys.forEach(function(key, index) {
    var found = rowIndex(model, key, index);
    if (found > index)
      model.move(found, index, 1);
    else if (found < 0)
      model.insert(index, { rowKey: key });
  });
  if (model.count > keys.length)
    model.remove(keys.length, model.count - keys.length);
}

/** Index of `key` in the model at or after `from`, or -1. */
function rowIndex(model, key, from) {
  for (var index = from; index < model.count; index++) {
    if (model.get(index).rowKey === key)
      return index;
  }
  return -1;
}
