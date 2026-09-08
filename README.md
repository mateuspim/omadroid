# DroidLink

An Omarchy bar widget for discovering Android Debug Bridge (ADB) devices over
USB and wireless mDNS, then launching scrcpy with chosen video and audio
settings.

## Features

- **Devices:** parallel `adb devices -l` and Avahi-based mDNS discovery;
  device model/name, serial or service identity, status, and transport. The bar
  badge counts authorized, ready transports. Refresh on open and every 15 seconds
  by default; the existing widget setting accepts 5–3600 seconds.
- **Wireless:** explicit connect, targeted disconnect, six-digit wireless
  pairing, and manual `IP:port` / `hostname:port` / `[IPv6]:port` entry.
- **Mirror:** select an authorized device, choose a built-in or saved profile,
  and launch scrcpy. Change resolution, FPS, H.264/H.265/AV1 codec, video bitrate,
  audio forwarding, recording, screen-off, and fullscreen independently. Launch
  **Audio only** to listen in the background without a scrcpy window
  (`--no-video --no-window`); optional audio-only recordings are saved as `.mka`.
  Use **Stop audio** in DroidLink to end the session.

The popup follows the active Omarchy theme and uses its native buttons, inputs,
dropdowns, typography, and keyboard focus styles. Tab moves between controls;
Enter/Space activates buttons; Escape dismisses the popup (or an open dropdown
first). Large device lists and forms scroll within the available screen height.

## Requirements and enabling

Requires Omarchy's Quickshell shell, Qt 6.5+, `adb`, Bash, `awk`, GNU coreutils
(`timeout`), Avahi (`avahi-browse` and a running `avahi-daemon`), and
scrcpy 2.0+ for mirroring. This implementation was checked against the
installed scrcpy 4.1 command-line options. Node is only needed for development
tests; there are no npm packages or Python runtime helpers.

The existing development link is:

```text
~/.config/omarchy/plugins/pym.droidlink → /home/me/Projects/droidlink
```

If the widget is not already in the bar, enable it with:

```bash
omarchy plugin enable pym.droidlink --section right
```

This repository preserves plugin ID `pym.droidlink`, the `Panel.qml` entry point,
and the existing manifest settings schema. It does not modify packaged Omarchy
files. Omarchy watches the user plugin directory for updates.

## Connecting a device

For USB, enable USB debugging, connect a data cable, unlock Android, and accept
the authorization prompt. The popup shows unauthorized, offline, permission,
recovery, and other ADB states; only `device` state enables mirroring. USB is
disconnected by unplugging the cable: `adb disconnect` only disconnects network
transports.

For Android wireless debugging, keep the phone and computer on the same network:

1. Enable Developer options → Wireless debugging on Android.
2. For a new host, open **Pair device with pairing code**. Select **Pair…** on
   the discovered pairing service, or enter its pairing address in Wireless.
3. Enter the six-digit code and select **Pair**.
4. Use the address on the main Wireless debugging page to **Connect**. This is
   normally a different port. Refresh discovery after pairing if necessary.

Pairing codes are passed on stdin, cleared after submission or dismissal, and
never saved in profiles or included in command arguments. Pairing grants ADB
trust; disconnecting does not forget that trust. Forget the host on Android to
revoke it. The plugin issues connection commands only on explicit clicks;
ADB itself may automatically connect to previously trusted mDNS services.

Discovery recognizes `_adb._tcp`, `_adb-tls-connect._tcp`, and
`_adb-tls-pairing._tcp`. Exact service/endpoint matches are merged with connected
wireless transports; USB and Wi-Fi remain separate transports, and pairing ports
remain distinct. mDNS does not supply a reliable hardware serial or model name,
so unconnected entries explicitly show a service identity instead.

The plugin invokes `bash discover-mdns.sh` using its resolved plugin path. The
script queries only those three Android service types through `avahi-browse`,
resolves them in parallel, and bounds each query to eight seconds. It emits
resolved Avahi records; the plugin decodes names, deduplicates endpoints, and
adds interface scopes to link-local IPv6 addresses. Pairing and connection ports
remain distinct. Results from successful queries survive a partial scan failure.

This path does not invoke `adb mdns services` and works independently of ADB's
mDNS build support. If Avahi is missing or its daemon is unavailable, the popup
reports the error and keeps USB and manual wireless controls available. The
script does not start or configure the daemon. Some networks block multicast.
No automatic ADB server restart, TCP-mode switch, package installation, or broad
disconnect is performed.

## Mirroring and profiles

| Profile | Maximum edge | FPS | Codec | Video bitrate | Audio |
| --- | --- | --- | --- | --- | --- |
| Balanced | 1080 px | 60 | H.264 | 8 Mbps | On |
| Low bandwidth | 720 px | 30 | H.264 | 4 Mbps | Off |
| High quality | Native | 60 | H.265 | 20 Mbps | On |

Resolution is the longest-edge limit, preserving aspect ratio; it is not a fixed
width × height. Native resolution and unlimited FPS omit those limits. Supported
FPS and encoders depend on the phone. Audio forwarding requires Android 11+;
Android 11 should be unlocked at launch. Unsupported audio may fall back to video
only. See the [upstream audio guide](https://github.com/Genymobile/scrcpy/blob/master/doc/audio.md).

Edit the options and save them with a custom name (up to 30 profiles). Saving an
existing custom name updates it. Built-in profiles cannot be overwritten. Saved
profiles, the last selected profile, and recording folder persist in
`$XDG_CONFIG_HOME/omarchy/droidlink.ini` (normally
`~/.config/omarchy/droidlink.ini`). Unsaved changes last until the widget reloads.
**Reset** restores edited options from the profile selected before those edits. It
does not modify Omarchy settings, saved profiles, the recording folder, or any
device connection.

Recording creates a unique timestamped `.mkv` file in the selected existing,
writable folder; the default is your home directory. Audio-only sessions instead
create `.mka` files. The session displays its exact path. Audio is included only
when forwarding is enabled and supported.
Use **Stop mirroring** or close the scrcpy window to finalize a recording.
Closing the popup or switching tabs leaves mirroring running. One session runs
per widget; stop it before starting another. Stop before reloading/removing the
plugin or restarting the shell. A vanished device selection is never silently
replaced by another phone.

All external programs use argument arrays, not shell interpolation. Mirroring
uses Quickshell's tracked-process termination: Stop sends `TERM` to scrcpy so
it can close streams and finalize recordings, then force-kills only a session
that fails to exit. Discovery
and ADB actions have bounded timeouts; captured diagnostics are bounded and shown
in the popup. ADB's failure messages are checked even when it exits with code 0.

## Development

Validate the plugin:

```bash
omarchy plugin validate /home/me/Projects/droidlink
node tests/model.test.cjs
node tests/mdns.test.cjs
bash tests/smoke.sh
DROIDLINK_TEST_CASE=avahi_unavailable bash tests/smoke.sh
```

The two Node suites run offline; the shell-helper suite uses a fake Avahi command
and covers partial failures, timeouts, removals, and temporary-file cleanup.
Ask before running live discovery or desktop tests in an active user session.

The smoke test needs access to a running Wayland session. It creates an isolated
hidden QML shell, temporary settings, and fake ADB/Avahi/scrcpy executables. It checks
discovery/merging, stdin pairing, connect/disconnect, failure reporting, timeouts,
missing executables, profile persistence, launch options, graceful stop, and
stale selection handling without touching real devices or the bar configuration.
Temporary test files are removed on exit.

For a visual review, create a temporary directory and run
`DROIDLINK_PREVIEW_DIR=/absolute/path/to/that/directory bash tests/smoke.sh`.
This briefly opens a separate preview window with fake devices, captures its three tabs,
and exits. Preview requires the QtTest QML module.

The original implementation milestones were validated in order: read-only USB/mDNS popup,
connection controls, then scrcpy profiles. Manifest validation only checks the
manifest and file layout; the QML and fixture tests exercise runtime behavior.
During development on this host, live ADB reported no attached devices and
`mdns is not supported by this version of adb`. The separate Avahi discovery
script replaces that unsupported discovery path. Its ten model tests and four
offline shell-helper fixtures pass, along with shell/QML syntax and manifest
validation. Live Avahi discovery and the updated desktop integration have not
been tested. End-to-end pairing, mirroring,
audio, recording media, and device screen control still need a physical-device
check. Fixture tests do not establish hardware compatibility.

Discovery output: [Avahi browser implementation](https://github.com/avahi/avahi/blob/master/avahi-utils/avahi-browse.c).
Protocol references: [ADB Wi-Fi architecture](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md)
and [scrcpy video options](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md).
