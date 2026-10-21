# Settings file

OmaDroid keeps its options in its own INI file, never in Omarchy's
configuration:

```
$XDG_CONFIG_HOME/omarchy/omadroid.ini     (default ~/.config/omarchy/omadroid.ini)
```

The path comes from `SettingsFile.omadroidIniUrl` and is computed when each
`Core.Settings` is constructed (an empty location made QSettings fail to
initialize). Four QML components each own a group of keys; Qt writes the file
on change.

## Permissions

`scripts/settings-file.sh PATH` runs once at startup (from `Preferences.qml`).
It creates the file empty if it is missing, with `umask 077`, and removes
group and other permissions (`chmod go=`). It never changes the content. Qt
keeps the permissions when it replaces the file on save, so the file stays
600.

## `[preferences]` (`Preferences.qml`)

Set from the popup's Settings page through the discovery service
(`setPreference(name, value)`); unknown names throw.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `refreshIntervalSec` | int | `15` | Seconds between `adb devices -l` polls, used only while `adb track-devices` isn't running. Clamped to 5–3600 on read and write; a non-number reads as 15. |
| `wakeOnLaunch` | bool | `true` | Wake the device before a session starts. |
| `unlockOnLaunch` | bool | `false` | Unlock with the saved PIN before a session starts. |
| `wakeOnConnect` | bool | `false` | Wake a device when it becomes ready. |
| `unlockOnConnect` | bool | `false` | Unlock a device when it becomes ready. |
| `lastTextTarget` | string | `""` | Serial the Send text overlay typed on last; preselected while it is ready. |

## `[autoConnect]` (`AutoConnect.qml`)

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | Connect remembered devices when they announce Wireless debugging. |
| `trustedJson` | string (JSON array) | `"[]"` | Device keys of phones that were ready over Wireless debugging. `AutoConnect.parseKeys` keeps only strings matching `^adb-[!-~]{1,128}$`; bad JSON reads as `[]`. The newest 50 are kept; a key is removed when its device refuses the connection. |

## `[General]` (no category)

`MirrorOptions.qml` and `WebcamOptions.qml` use the file without a category,
so Qt stores their keys under `[General]`.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `profilesJson` | string (JSON array) | `"[]"` | Saved mirror profiles (shape below). |
| `lastProfile` | string | `"Balanced"` | Profile selected last; an unknown name falls back to the first built-in. |
| `recordingFolder` | string | `$HOME` | Folder for mirror recordings; must be absolute when recording. |
| `webcamJson` | string (JSON object) | `""` | Webcam options (shape below). |

### Mirror profile

`Model.savedProfiles` keeps at most 30 entries that pass `Model.validProfile`
and whose names are unique and not `Custom` or a built-in name (`Balanced`,
`Low bandwidth`, `High quality`).

| Field | Allowed values |
| --- | --- |
| `name` | non-empty string, up to 48 characters |
| `maxSize` | `"0"` (no limit), `"720"`, `"1080"`, `"1440"`, `"1920"`, `"2560"`, `"3840"` |
| `fps` | `"0"` (no limit), `"15"`, `"24"`, `"30"`, `"60"`, `"90"`, `"120"` |
| `codec` | `"h264"`, `"h265"`, `"av1"` |
| `bitrate` | Mbps: `"2"`, `"4"`, `"8"`, `"12"`, `"16"`, `"20"`, `"32"`, `"50"`, `"60"` |
| `audio`, `record`, `screenOff`, `fullscreen` | boolean |
| `keepActive` | boolean, optional; when absent, `screenOff` decides (older profiles) |

### Webcam options

`Webcam.webcamSettings` reads each known key whose type matches its default
and drops everything else; bad JSON reads as the defaults.

| Field | Default | Checked when the command is built (`Webcam.webcamCommand`) |
| --- | --- | --- |
| `camera` | `"front"` | `front`, `back`, `external` or `id:<id>` |
| `orientation` | `"0"` | `0`, `90`, `180`, `270`, `flip0` … `flip270` |
| `preset` | `"call"` | UI preset name |
| `size` | `"1920x1080"` | `auto` or `WIDTHxHEIGHT` |
| `fps` | `"30"` | 1–999 |
| `bitRate` | `"12"` | Mbps, 1–99 |
| `codec` | `"h265"` | `h264`, `h265`, `av1` |
| `zoom` | `"1"` | positive number |
| `torch` | `false` | boolean |
| `buffer` | `"0"` | milliseconds, 0–9999 |

## Other state

The settings file is not the only place OmaDroid stores data; see the storage
table in [architecture.md](../architecture.md#storage) for the keyring,
`$XDG_STATE_HOME/omadroid`, the runtime folder and the cache.
