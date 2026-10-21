# Script contract

QML never builds shell strings. It runs the helpers in `scripts/` with an
argument array (`Command.qml`, or `CommandStream.qml` for long-running ones)
and parses what they print. This page lists what each helper accepts and what
the parsers in the `.js` modules expect. Change a format here and in its
parser together, with a test for both.

## Shared rules

- **stdout** carries results, as plain text lines; a human-readable message
  when there is no structured result.
- **stderr** carries the reason for a failure, written for the user: QML shows
  it (through `Model.commandError`) when the exit code is not 0.
- **Exit codes:** 0 is success. `1` is an adb or usage error unless a script
  says otherwise; `2` an invalid argument; `127` a missing program.
- **Serials** passed to `device-power.sh`, `device-volume.sh`,
  `go-wireless.sh` and `send-text.sh` must match
  `^[A-Za-z0-9._:@-]{1,128}$` (`adb-lib.sh valid_serial`).
- **Secrets and typed text** go on stdin, never in argv.
- `LC_ALL=C` in scripts that parse device output.

## Discovery

| Command | stdout | Parser |
| --- | --- | --- |
| `adb track-devices -l` (stream) | adb's framed protocol: 4 hex digits of length, then that many bytes of `adb devices -l` lines | `Model.takeTrackFrames`, `Model.parseDevices` |
| `adb devices -l` (fallback poll) | adb's listing | `Model.parseDevices` |
| `discover-mdns.sh` (stream, until stopped) | `avahi-browse --resolve --parsable` lines as they arrive (`=` resolved, `-` removed) for `_adb._tcp`, `_adb-tls-connect._tcp`, `_adb-tls-pairing._tcp`. Exits non-zero once any browser stops. | `Model.applyMdnsLine`, `Model.parseMdns` |
| `device-names.sh SERIAL…` | `serial<TAB>name` per device whose Android device name is set (control characters removed, at most 64 characters). Always exits 0. | `Model.parseDeviceNames` |
| `device-info.sh SERIAL…` | `serial<TAB>key<TAB>value` lines; always exits 0. Keys below. | `DeviceInfo.parseDeviceInfo` |

`device-info.sh` keys:

| Key | Value |
| --- | --- |
| `battery_level`, `battery_status`, `battery_temp` | integers from `dumpsys battery` (temperature in tenths of °C) |
| `battery_plugged` | comma list of `ac`, `usb`, `wireless` |
| `android`, `sdk` | release string; API level |
| `mem_kb` | total memory in KiB |
| `screen` | `WIDTHxHEIGHT` |
| `internal` | `usedKb:totalKb` of `/data` |
| `external_<id>` | `<id>:<sd|usb|external>:usedKb:totalKb` for each mounted removable volume |

## Connecting

| Command | Contract |
| --- | --- |
| `adb connect\|disconnect\|pair HOST:PORT` | Built by `Model.adbCommand`; `pair` gets the pairing code on stdin. Success is exit 0 and adb's own wording (`connected to`, `successfully paired to`, `disconnected`), checked by `Model.actionSucceeded`. |
| `qr-pair.sh` | `service<TAB>omadroid-xxxxxxxx`, `password<TAB>…`, then one `row<TAB>0110…` line per QR row (1 = dark module, no quiet zone). Needs `qrencode`. Parsed by `Pairing.parseQrPairing`. |
| `go-wireless.sh SERIAL` | `Connected to HOST:PORT. You can unplug the cable.` Exit 2: not on Wi-Fi; 3: Wireless debugging didn't start; 4: refused or not authorized. QML shows the last stdout line. |

## Sessions: `session.sh`

Run with an absolute path: `launch` re-runs the script in a new terminal.

| Command | stdout |
| --- | --- |
| `check` | One missing prerequisite per line (`adb`, `scrcpy`, `foot or an Omarchy default terminal`); empty when all are present. |
| `status` | `active`, then serial, type (`mirror`/`audio`/`webcam`), recording path (or the webcam's `/dev/videoN`; empty for none), PID, one per line. Or `inactive`, optionally followed by a webcam error sentence from the last log. |
| `path` | The state file's path, which widgets watch instead of polling. |
| `wait` | Blocks until the session ends, then prints `inactive`. |
| `launch SERIAL TYPE RECORDING -- scrcpy ARGS…` | `Session started in the hidden OmaDroid terminal.` TYPE is `mirror`, `audio`, `webcam` (or legacy `0`/`1`). Fails if a session is active or starting, a program or terminal is missing, the recording folder isn't writable, or (webcam) the output check fails or Android is older than 12. |
| `stop` | `Session stopped.`, `Session force-stopped after scrcpy did not exit cleanly.` or `No active OmaDroid session.` |
| `rotate lock 0-3 \| free \| query` | `query`: `free`, or `lock N` plus `owned` when OmaDroid set it. Parsed by `ScreenRotation.parseRotationState`. |

The scrcpy argument lists come from `Model.scrcpyCommand`,
`Model.audioOnlyCommand` and `Webcam.webcamCommand`, which validate every
option first.

## Device power: `device-power.sh`

| Command | stdout |
| --- | --- |
| `status SERIAL` | `keep=on\|off running=1\|0 secret=none\|saved\|stale\|blocked` (`DevicePower.parsePowerStatus`) |
| `keep-awake on\|off SERIAL` | `Keeping the screen on.` / `Screen timeout restored.` |
| `connected WAKE UNLOCK SERIAL…` | Restarts wanted keepers, then wakes/unlocks (`0`/`1` each). |
| `wake SERIAL` | `Device woken.` |
| `unlock SERIAL` | `Device unlocked.` or `Device is awake and unlocked.` |
| `lock SERIAL` | `Device locked.` or `Screen off; Android locks it after the device's lock delay.` |
| `secret-set SERIAL` (secret on stdin) | `Unlock PIN saved in the keyring.` |
| `secret-clear SERIAL` | `Unlock PIN removed.` |

Exit codes: 3 no secret saved, 4 unlock paused after a failed try, 5 keyring
unavailable, 6 the device identity doesn't match the saved secret.

## Sound: `device-volume.sh`

`status SERIAL` prints, parsed by `SoundVolume.parseVolumeStatus`:

```
mode samsung|appops
master 0|1|-
ringer normal|vibrate|silent|-
stream KEY INDEX VOLUME MIN MAX MUTED          (KEY: call system ring media alarm notification assistant)
app UID playing|paused VOLUME|- MUTED|- PACKAGE LABEL…
```

Changes: `stream SERIAL KEY set N|raise|lower|mute|unmute`,
`app SERIAL UID set 0-100|mute|unmute`, `master SERIAL mute|unmute`,
`ringer SERIAL normal|vibrate|silent`, `key SERIAL up|down|mute`. Exit 6: the
action needs audio codes that couldn't be read or didn't verify.

`audio-codes.py framework.jar` prints `method=code` lines (for example
`setAppVolume=293`) and refuses a table it can't check.

## Send text: `send-text.sh SERIAL`

stdin: one step per line, `text:TEXT` or `key:NAME` (for example
`key:ctrl+a`, `text:hello`, `key:enter`). Every step is checked before
anything is sent; then all run in one `adb shell`. Prints nothing on success;
exit 2 when a step can't be sent. Built by `SendText.sendTextCommand`.

## Hotkey: `hotkey.sh`

`status` → `installed COMBO` or `none`; `set COMBO` → `installed COMBO`;
`remove` → `none`. COMBO is normalized to modifiers in the order
`SUPER CTRL ALT SHIFT` then one key, e.g. `SUPER + ALT + D`. Exit 2: the
combination is already bound elsewhere.

## Webcam

| Command | Contract |
| --- | --- |
| `webcam-devices.sh list` | `/dev/videoN<TAB>label` per v4l2loopback output. With none, stderr names the reason: `no-output`, `module-not-loaded`, `module-unavailable` or `missing-package`. |
| `webcam-devices.sh check /dev/videoN` | Nothing on success; a sentence on stderr when the output is missing, not writable, or held by another app. |
| `webcam-devices.sh cameras SERIAL` | `scrcpy --list-camera-sizes` output, parsed by `Webcam.parseCameraList`. |
| `webcam-preview.sh /dev/videoN RUNTIME/preview-ID.jpg` | Runs ffmpeg until stopped, rewriting the JPEG 12 times a second. Exit 3: readers and scrcpy disagree on the size. |
| `webcam-setup.sh open install\|load` | Opens a visible terminal running the privileged setup; see [SECURITY.md](../../SECURITY.md). |

## Settings file: `settings-file.sh PATH`

Prints nothing; creates PATH if missing and makes it owner-only. See
[settings](settings.md#permissions).
