# Environment variables

OmaDroid has no user-facing environment switches: everything a user sets is in
[the settings file](settings.md). The variables below are read by the code
for standard locations, by the plugin itself between its own processes, or as
test seams so the suites can point scripts at fixtures instead of the real
system.

## Standard variables

| Variable | Read by | Use |
| --- | --- | --- |
| `XDG_CONFIG_HOME` (else `$HOME/.config`) | QML, `hotkey.sh` | `omarchy/omadroid.ini`; `hypr/bindings.lua` |
| `XDG_STATE_HOME` (else `$HOME/.local/state`) | `device-power.sh` | `omadroid/devices/<serial>/` markers |
| `XDG_CACHE_HOME` (else `$HOME/.cache`) | `device-volume.sh` | `omadroid/` audio codes and app names |
| `XDG_RUNTIME_DIR` (else `/tmp`) | `proc-lib.sh` | `omadroid-$UID/` session and keeper state; refused if it is a symlink or not owned by the user |
| `HOME` | QML, scripts | Fallbacks above; default recording folder |
| `OMARCHY_PATH` | `SendText.qml` | Omarchy's install path, from the shell |

## Set by OmaDroid itself

| Variable | Set by | Read by | Meaning |
| --- | --- | --- | --- |
| `OMADROID_KEEP_READERS=1` | `MirrorSession.qml` on webcam **Apply** | `webcam-devices.sh check` | Don't refuse an output that another app is reading: a call reading it bridges the restart. |

## Test seams

Scripts read these so tests can replace a system path or binary. They have
defaults that match a normal system and should not be set in daily use.

| Variable | Default | Read by |
| --- | --- | --- |
| `OMADROID_FOOT` | `foot` | `terminal-lib.sh`: the foot binary |
| `OMADROID_POLL_DELAY` | `0.5` | `go-wireless.sh`: seconds between polls |
| `OMADROID_HYPR_BINDINGS` | `$XDG_CONFIG_HOME/hypr/bindings.lua` | `hotkey.sh` |
| `OMADROID_VIDEO_SYSFS` | `/sys/class/video4linux` | `webcam-devices.sh`, `webcam-preview.sh` |
| `OMADROID_VIDEO_DEV` | `/dev` | `webcam-devices.sh` |
| `OMADROID_VIDEO_MODULE_SYSFS` | `/sys/module/v4l2loopback` | `webcam-devices.sh` |
| `OMADROID_ETC` | `/etc` | `webcam-setup.sh` |

## Test harness only

Read only by files in `tests/`:

- `OMADROID_TEST_CASE`: runs a suite's variant (`no_track`,
  `avahi_unavailable`); `tests/run-all.sh` sets it.
- `OMADROID_PREVIEW_DIR` (absolute directory), `OMADROID_PREVIEW_PAGES`
  (comma-separated views) and `OMADROID_PREVIEW_QML` (capture script): the
  offscreen preview mode of `tests/smoke.sh`; see the
  [development runbook](../runbooks/development.md#offscreen-previews).
- `OMADROID_SCRCPY_STAY=1`: the fake scrcpy keeps mirror and audio sessions
  running (camera sessions always stay), for session-step previews.
- Fixture and log locations for the fakes in `tests/mock-*.sh`, such as
  `OMADROID_ADB_LOG`, `OMADROID_POWER_DIR`, `OMADROID_KEYRING`,
  `OMADROID_TEXT_DIR`, `OMADROID_VOLUME_DIR`, `OMADROID_TEST_CAMERAS`. Each
  suite sets the ones its fakes need; see the suite.

Suites print a marker such as `OMADROID_SMOKE_OK` or `OMADROID_POWER_FAILED`;
`tests/run-all.sh` prints `OMADROID_ALL_OK` when every suite passed.
