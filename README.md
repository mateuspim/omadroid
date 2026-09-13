# DroidLink

An Omarchy bar widget for discovering Android Debug Bridge (ADB) devices over
USB and wireless mDNS, then launching scrcpy with chosen video and audio
settings.

## Features

- **Devices:** one process-wide discovery service runs parallel `adb devices -l` and Avahi-based mDNS discovery for every monitor;
  device model/name, serial or service identity, status, and transport. The bar
  badge counts authorized, ready transports. Refresh on open and every 15 seconds
  by default; the existing widget setting accepts 5–3600 seconds.
- **Wireless:** explicit connect, targeted disconnect, six-digit wireless
  pairing, pairing prefill from discovered services, and manual
  `IP:port` / `hostname:port` / `[IPv6]:port` entry.
- **Mirror:** select an authorized device, choose a built-in or saved profile,
  and launch scrcpy. Change resolution, FPS, H.264/H.265/AV1 codec, video bitrate,
  audio forwarding, recording, screen-off, and fullscreen independently. Launch
  **Audio only** to listen in the background without a scrcpy window
  (`--no-video --no-window`); optional audio-only recordings are saved as `.mka`.
  Use **Stop audio** in DroidLink to end the session.

The popup follows the active Omarchy theme and uses its native buttons, inputs,
dropdowns, typography, and keyboard focus styles. Tab moves between controls;
Enter/Space activates buttons; Escape dismisses the popup (or an open dropdown
first). Device lists and the Wireless form scroll when needed; the compact
Mirror page keeps its options, primary actions, and session controls visible
without scrolling.

## Requirements and enabling

Requires Omarchy's Quickshell shell, Qt 6.5+, `adb`, Bash, `awk`, GNU coreutils
(`timeout`), Avahi (`avahi-browse` and a running `avahi-daemon`), and
scrcpy 4.1+ for mirroring and idle prevention. This implementation was checked against the
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
2. Choose **Connect** on the discovered wireless connection service. If this
   workstation is already paired, it connects immediately.
3. If the connection fails, DroidLink opens Pair with the discovered host/IP
   locked in place. Open **Pair device with pairing code** on Android, then
   enter only its separate pairing port and six-digit code. If Android's
   pairing service is already advertised, its actual pairing port is filled in.
4. Select **Pair**. DroidLink refreshes discovery so the connection service can
   be used. Direct Pair on an advertised pairing service and the fully manual
   Pair and Connect forms remain available in Wireless.

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

### Phone screen and authentication

During a video session, **Phone screen on** lights the physical display for
passwords or fingerprint authentication; **Phone screen off** darkens it again
without restarting the session or interrupting its recording. The buttons send
scrcpy's Alt+Shift+O / Alt+O shortcuts to the owned scrcpy process through
Hyprland's Lua dispatcher. They do not target the focused window. Dispatch
acknowledgement is reported as a request, not as verified phone display state.
If dispatch fails, use those shortcuts directly in the scrcpy window.

Android or an app can exclude protected content from capture. Authenticate on
the physical phone in that case; DroidLink does not detect protected prompts
automatically or change Android's capture protections.

**Prevent idle sleep** uses scrcpy 4.1's `--keep-active`, which also works without
a charger. Selecting **Device screen off** enables it; it can be unchecked
independently before launch. Older saved screen-off profiles also default to
idle prevention unless explicitly opted out. This may delay automatic locking
while mirroring: lock the phone yourself when needed. It applies only to video
sessions and lasts for the session; editing launch options does not reconfigure
a running session.

This addresses normal inactivity sleep, not forced locks or every manufacturer's
display behavior. Android can still light the screen after physical power-button
or lock/wake events. Use **Phone screen off** again instead of restarting scrcpy.
See [scrcpy's device controls](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/device.md).

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
node tests/screen-power.test.cjs
bash tests/shared-discovery.sh
DROIDLINK_TEST_CASE=avahi_unavailable bash tests/shared-discovery.sh
bash tests/smoke.sh
DROIDLINK_TEST_CASE=avahi_unavailable bash tests/smoke.sh
```

All Node suites run offline (`node --test tests/*.test.cjs`); the shell-helper suite uses a fake Avahi command
and covers partial failures, timeouts, removals, and temporary-file cleanup.
Ask before running live discovery or desktop tests in an active user session.
Screen-power tests execute the command builder and QML method bodies with fake
commands/timers; they do not exercise QML bindings or deliver real compositor
shortcuts. Physical authentication, screen-power changes, and idle behavior still
require an approved real-device test.

The shared-discovery test creates two real widget consumers of one injected service and
uses fake ADB/Avahi executables to prove startup is singular and queued refreshes never
overlap. The smoke test needs access to a running Wayland session. It creates an isolated
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
