import QtQuick
import "Model.js" as Model

Item {
  id: root
  // Poll interval for `adb devices -l`, used only while `adb track-devices`
  // isn't running (adb missing, server restarting).
  property int intervalSec: 15
  property bool active: true
  // Plugin settings forwarded by DiscoveryConsumer.
  property bool wakeOnConnect: false
  property bool unlockOnConnect: false
  // Raw `adb devices -l` rows; `devices` adds the Android device names.
  property var adbDevices: []
  // Serial → Android device name, "" when unset or unreadable. Asked once per
  // connection, not on every scan.
  property var deviceNames: ({})
  property var namesRequested: []
  // Serial → parsed device-info.sh result (battery, storage, …) and when it was
  // read. Details are only shown in the popup, so they are read while a
  // consumer holds mDNS (an open popup) and refreshed once they are a minute old.
  property var deviceInfo: ({})
  property var infoReadAt: ({})
  property var infoRequested: []
  property int infoMaxAgeSec: 60
  readonly property var devices: Model.withDeviceInfo(Model.withDeviceNames(adbDevices, deviceNames), deviceInfo)
  property var services: []
  property string devicesError: ""
  // mdnsError is the short text shown on the page; mdnsLevel is "", "warning" or "error".
  property string mdnsError: ""
  property string mdnsLevel: ""
  property string mdnsDetails: ""
  // Service name → model from earlier scans, to name a device that stops answering.
  property var knownNames: ({})
  property string updatedAt: ""
  property bool initialized: false
  property bool refreshPending: false
  // `adb track-devices` pushes every change of the device list, so nothing
  // polls while it runs. It is restarted with a growing delay when it stops.
  property bool tracking: false
  property string trackBuffer: ""
  property int trackRetries: 0
  // mDNS results are only shown in the popup, so the Avahi browsers run while
  // a consumer holds it (an open popup). Standalone hosts can opt into
  // background browsing.
  property bool mdnsInBackground: false
  property var mdnsHolders: []
  readonly property bool mdnsWanted: active && (mdnsInBackground || mdnsHolders.length > 0)
  // Resolved Avahi records of the current stream, mutated in place by
  // Model.applyMdnsLine; `services` is published from them.
  property var mdnsRecords: ({})
  property var mdnsErrorLines: []
  property int mdnsExitCode: 0
  // Briefly true after the browsers (re)start. The previous services stay
  // shown until then, so reopening the popup doesn't flicker the rows.
  property bool mdnsSettling: false
  readonly property string namesScript: decodeURIComponent(Qt.resolvedUrl("device-names.sh").toString().replace(/^file:\/\//, ""))
  readonly property string infoScript: decodeURIComponent(Qt.resolvedUrl("device-info.sh").toString().replace(/^file:\/\//, ""))
  readonly property string mdnsScript: decodeURIComponent(Qt.resolvedUrl("discover-mdns.sh").toString().replace(/^file:\/\//, ""))
  readonly property bool busy: usb.busy || mdnsSettling
  readonly property var rows: Model.deviceRows(devices, services)
  readonly property int readyCount: devices.filter(row => row.status === "device").length

  // An explicit refresh (button, F5, after connect/pair) re-reads adb and
  // restarts the Avahi browsers, even though both are followed live. Browsers
  // still settling were just started (a popup opening), so they are kept.
  function refresh() {
    if (usb.busy) {
      refreshPending = true;
      return;
    }
    refreshPending = false;
    pollDevices();
    if (mdnsWanted && !mdnsSettling)
      startMdns();
  }

  function pollDevices() {
    if (!usb.busy)
      usb.start(["adb", "devices", "-l"], 12);
  }

  // Rescans that found nothing new keep the same arrays, so bound views
  // (device cards, the mirror device list) aren't rebuilt.
  function setDevices(rows) {
    if (Model.sameData(rows, adbDevices))
      return;
    adbDevices = rows;
    refreshNames();
    refreshInfo();
  }

  function markUpdated() {
    initialized = true;
    updatedAt = Qt.formatTime(new Date(), "HH:mm:ss");
  }

  function startTracker() {
    trackBuffer = "";
    tracker.start(["adb", "track-devices", "-l"]);
  }

  function readTrackFrames(data) {
    var frames;
    try {
      frames = Model.takeTrackFrames(trackBuffer + data);
    } catch (e) {
      // Out of step with the framing; a fresh tracker starts with a full list.
      console.warn(JSON.stringify({ droidlink: "track-devices", error: e.message }));
      tracker.stop();
      trackerStopped();
      return;
    }
    trackBuffer = frames.rest;
    if (!frames.payloads.length)
      return;
    tracking = true;
    trackRetries = 0;
    devicesError = "";
    setDevices(Model.parseDevices(frames.payloads[frames.payloads.length - 1]));
    markUpdated();
  }

  function trackerStopped() {
    tracking = false;
    // Keeps the list current meanwhile and reports why adb failed.
    pollDevices();
    trackRetry.interval = Math.min(60, Math.pow(2, trackRetries)) * 1000;
    trackRetries++;
    trackRetry.restart();
  }

  function startMdns() {
    mdnsRecords = {};
    mdnsErrorLines = [];
    mdnsExitCode = 0;
    mdnsSettling = true;
    mdnsSettle.restart();
    mdnsRetry.stop();
    mdns.start(["bash", mdnsScript]);
  }

  function stopMdns() {
    mdns.stop();
    mdnsRetry.stop();
    mdnsSettle.stop();
    mdnsSettling = false;
  }

  function noteMdnsError(line) {
    var lines = mdnsErrorLines.filter(known => known !== line);
    lines.push(line);
    mdnsErrorLines = lines.slice(-20);
    if (!mdnsSettling)
      Qt.callLater(publishServices);
  }

  function publishServices() {
    // The browsers race, so arrival order varies; sorting keeps an unchanged
    // set equal to the last one.
    var found = Model.parseMdns(Object.keys(mdnsRecords).sort().map(key => mdnsRecords[key]).join("\n"));
    var names = Object.assign({}, knownNames);
    found.forEach(row => {
      if (row.model)
        names[row.serial] = row.model;
    });
    if (!Model.sameData(names, knownNames))
      knownNames = names;
    var status = Model.mdnsStatus(mdnsExitCode, mdnsErrorLines.join("\n"), found, names);
    mdnsError = status.text;
    mdnsLevel = status.level;
    mdnsDetails = status.details;
    if (!Model.sameData(found, services))
      services = found;
  }

  function refreshNames() {
    var ready = adbDevices.filter(row => row.status === "device").map(row => row.serial);
    var kept = {};
    ready.forEach(serial => {
      if (serial in deviceNames)
        kept[serial] = deviceNames[serial];
    });
    if (!Model.sameData(kept, deviceNames))
      deviceNames = kept;
    var pending = ready.filter(serial => !(serial in kept));
    if (!pending.length || names.busy)
      return;
    namesRequested = pending;
    names.start(["bash", namesScript].concat(pending), 8);
  }

  function refreshInfo() {
    var ready = adbDevices.filter(row => row.status === "device").map(row => row.serial);
    var kept = {}, keptAt = {};
    ready.forEach(serial => {
      if (serial in infoReadAt) {
        kept[serial] = deviceInfo[serial];
        keptAt[serial] = infoReadAt[serial];
      }
    });
    if (!Model.sameData(kept, deviceInfo))
      deviceInfo = kept;
    infoReadAt = keptAt;
    if (!mdnsWanted || info.busy)
      return;
    var now = Date.now();
    var pending = ready.filter(serial => !(serial in keptAt) || now - keptAt[serial] >= infoMaxAgeSec * 1000);
    if (!pending.length)
      return;
    infoRequested = pending;
    info.start(["bash", infoScript].concat(pending), 8);
  }

  function holdMdns(owner, wanted) {
    var holders = mdnsHolders.filter(holder => holder !== owner);
    if (wanted)
      holders.push(owner);
    mdnsHolders = holders;
  }

  onMdnsWantedChanged: {
    if (!mdnsWanted)
      return stopMdns();
    startMdns();
    refreshInfo();
  }
  onActiveChanged: {
    if (active)
      return startTracker();
    tracker.stop();
    trackRetry.stop();
    tracking = false;
  }
  onBusyChanged: if (!busy) {
    markUpdated();
    if (refreshPending)
      Qt.callLater(refresh);
  }
  Component.onCompleted: {
    if (!active)
      return;
    startTracker();
    if (mdnsWanted)
      startMdns();
  }
  Timer {
    interval: Math.max(5, Math.min(3600, root.intervalSec)) * 1000
    running: root.active && !root.tracking
    repeat: true
    onTriggered: root.pollDevices()
  }
  Timer {
    id: trackRetry
    onTriggered: if (root.active)
      root.startTracker()
  }
  // Details are re-read once a minute while a popup is open.
  Timer {
    interval: root.infoMaxAgeSec * 1000
    running: root.mdnsWanted
    repeat: true
    onTriggered: root.refreshInfo()
  }
  Timer {
    id: mdnsSettle
    interval: 1500
    onTriggered: {
      root.mdnsSettling = false;
      root.publishServices();
    }
  }
  // An Avahi restart or a missing daemon stops the browsers; retry while wanted.
  Timer {
    id: mdnsRetry
    interval: 10000
    onTriggered: if (root.mdnsWanted)
      root.startMdns()
  }
  PowerOnConnect {
    readySerials: root.adbDevices.filter(row => row.status === "device").map(row => row.serial)
    started: root.initialized
    wake: root.wakeOnConnect
    unlock: root.unlockOnConnect
  }
  CommandStream {
    id: tracker
    splitMarker: ""
    onRead: data => root.readTrackFrames(data)
    onExited: code => root.trackerStopped()
  }
  CommandStream {
    id: mdns
    onRead: line => {
      if (Model.applyMdnsLine(root.mdnsRecords, line) && !root.mdnsSettling)
        Qt.callLater(root.publishServices);
    }
    onErrorRead: line => root.noteMdnsError(line.trim())
    onExited: code => {
      root.mdnsExitCode = code;
      mdnsSettle.stop();
      root.mdnsSettling = false;
      root.publishServices();
      mdnsRetry.restart();
    }
  }
  Command {
    id: usb
    onFinished: (code, output, error) => {
      root.devicesError = code === 0 ? "" : Model.commandError(code, output, error, "ADB discovery");
      root.setDevices(code === 0 ? Model.parseDevices(output) : []);
    }
  }
  Command {
    id: names
    onFinished: (code, output, error) => {
      var found = Model.parseDeviceNames(output);
      var merged = Object.assign({}, root.deviceNames);
      root.namesRequested.forEach(serial => {
        if (root.adbDevices.some(row => row.serial === serial))
          merged[serial] = found[serial] || "";
      });
      root.deviceNames = merged;
    }
  }
  Command {
    id: info
    onFinished: (code, output, error) => {
      var found = Model.parseDeviceInfo(output);
      var merged = Object.assign({}, root.deviceInfo), readAt = Object.assign({}, root.infoReadAt);
      var now = Date.now();
      root.infoRequested.forEach(serial => {
        if (!root.adbDevices.some(row => row.serial === serial))
          return;
        // A device that didn't answer keeps its last reading until the next attempt.
        if (found[serial] || !(serial in merged))
          merged[serial] = found[serial] || null;
        readAt[serial] = now;
      });
      if (!Model.sameData(merged, root.deviceInfo))
        root.deviceInfo = merged;
      root.infoReadAt = readAt;
    }
  }
}
