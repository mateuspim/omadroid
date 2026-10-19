import QtQuick
import QtCore as Core
import Quickshell
import "SettingsFile.js" as SettingsFile

// OmaDroid's options, set on the popup's Settings page and kept in its own
// omadroid.ini ([preferences]), never in Omarchy's configuration. Owned by
// the shared discovery service so every widget sees the same values.
Item {
  id: root
  readonly property string location: SettingsFile.omadroidIniUrl(Quickshell.env("XDG_CONFIG_HOME") || "", Quickshell.env("HOME"))
  readonly property string settingsScript: decodeURIComponent(Qt.resolvedUrl("scripts/settings-file.sh").toString().replace(/^file:\/\//, ""))
  // Seconds between `adb devices -l` polls, used only while `adb track-devices` isn't running.
  readonly property int refreshIntervalSec: clampInterval(stored.refreshIntervalSec)
  readonly property bool wakeOnLaunch: stored.wakeOnLaunch
  readonly property bool unlockOnLaunch: stored.unlockOnLaunch
  readonly property bool wakeOnConnect: stored.wakeOnConnect
  readonly property bool unlockOnConnect: stored.unlockOnConnect
  // Serial the Send text overlay typed on last; preselected while it is ready.
  readonly property string lastTextTarget: stored.lastTextTarget

  function clampInterval(seconds) {
    return Math.max(5, Math.min(3600, Math.round(Number(seconds) || 15)));
  }

  /** Change one option; booleans are coerced, the interval clamped to 5–3600 s.
   * Example: preferences.set("wakeOnConnect", true) */
  function set(name, value) {
    if (name === "refreshIntervalSec")
      return stored.refreshIntervalSec = clampInterval(value);
    if (name === "lastTextTarget")
      return stored.lastTextTarget = String(value || "");
    if (["wakeOnLaunch", "unlockOnLaunch", "wakeOnConnect", "unlockOnConnect"].indexOf(name) < 0)
      throw new Error("Unknown OmaDroid preference '" + name + "'; expected refreshIntervalSec, lastTextTarget, wakeOnLaunch, unlockOnLaunch, wakeOnConnect or unlockOnConnect.");
    stored[name] = !!value;
  }

  // omadroid.ini holds device ids and addresses, so it is made owner-only once
  // at startup; Qt keeps the permissions when it saves.
  Command {
    id: privateFile
  }
  Component.onCompleted: privateFile.start(["bash", settingsScript, decodeURIComponent(location.replace(/^file:\/\//, ""))], 5)

  // Defaults match the 0.7.0 manifest defaults.
  Core.Settings {
    id: stored
    location: root.location
    category: "preferences"
    property int refreshIntervalSec: 15
    property bool wakeOnLaunch: true
    property bool unlockOnLaunch: false
    property bool wakeOnConnect: false
    property bool unlockOnConnect: false
    property string lastTextTarget: ""
  }
}
