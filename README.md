# DroidLink

An Omarchy bar widget for discovering Android Debug Bridge (ADB) devices over
USB and wireless mDNS, then launching scrcpy with chosen video and audio
settings.

## Features

- **Devices:** one process-wide discovery service follows `adb track-devices -l`
  for every monitor, so plugging in, authorizing or losing a device shows at
  once without polling, plus Avahi-based mDNS discovery that follows the network
  while the popup is open; it shows
  device name, model, serial or service identity, status, and transport. The name
  is the one set on Android (Settings › About › Device name), read once per
  connection; devices without one show their model. Ready devices also show
  battery, Android version and storage used; **Details** adds temperature,
  SD card or USB drive storage, memory, and screen size with its aspect ratio.
  Sizes use 1000-based units (GB, TB), as Android's Settings does.
  These are read with one `adb shell` per device while the popup is open and
  refreshed once they are a minute old; nothing is read while it is closed. The
  session card shows the mirrored device's battery. The bar
  badge counts authorized, ready transports. **Refresh** (F5) re-reads ADB and
  restarts the Avahi browsers. If the ADB tracker stops (adb missing, its server
  restarting), DroidLink polls `adb devices -l` every 15 seconds by default (the
  Settings page accepts 5–3600 seconds) and retries the tracker with a growing
  delay of up to a minute.
- **Wireless:** pair by scanning a QR code with Android, **Go wireless** to
  move a USB device to Wi-Fi so the cable can be unplugged, explicit connect,
  targeted disconnect, six-digit wireless pairing, pairing prefill from
  discovered services, and manual `IP:port` / `hostname:port` / `[IPv6]:port`
  entry. See [Pair with a QR code](#pair-with-a-qr-code) and
  [Go wireless](#go-wireless).
- **Mirror:** select an authorized device, choose a built-in or saved profile,
  and launch scrcpy. Change resolution, FPS, H.264/H.265/AV1 codec, video bitrate,
  audio forwarding, recording, screen-off, and fullscreen independently. Launch
  **Audio only** to listen in the background without a scrcpy window
  (`--no-video --no-window`); optional audio-only recordings are saved as `.mka`.
  Use the four orientation buttons during a video session to lock the device to
  portrait, landscape, or either inverted orientation. **Auto rotate / reset**
  restores Android's sensor rotation. A lock set from DroidLink is released when
  the session ends; a lock set on the phone is kept. Use **Stop audio** in DroidLink to end an
  audio-only session. While a session runs, its controls (Stop, phone screen,
  rotation) come first and the options for the next launch fold under
  **Next session options**.
- **Keep awake, wake and unlock:** each ready device card has **Keep awake**,
  **Wake** (**Wake & unlock** once a PIN is saved) and **Unlock PIN…**. See
  [Keep awake and unlock](#keep-awake-and-unlock).

The popup follows the active Omarchy theme and uses its native buttons, inputs,
dropdowns, typography, and keyboard focus styles. Tab moves between controls;
Enter/Space activates buttons; Escape dismisses the popup (or an open dropdown
first). Device lists and the Wireless form scroll when needed; the compact
Mirror page keeps its options, primary actions, and session controls visible
without scrolling.

## Requirements and enabling

Requires Omarchy's Quickshell shell, Qt 6.5+, `adb`, Bash, `awk`, GNU coreutils
(`timeout`), util-linux (`flock`, `setsid`, `waitpid`), `secret-tool` (libsecret, only to save an unlock PIN), an Omarchy default terminal, Avahi
(`avahi-browse` and a running `avahi-daemon`), and scrcpy 4.1+ for mirroring and
idle prevention. `qrencode` is only needed to pair with a QR code. The bar and popup warn when `adb`, `scrcpy`, or a configured
default terminal is missing. This implementation was checked against the installed
scrcpy 4.1 command-line options. Node is only needed for development tests;
there are no npm packages or Python runtime helpers.

The existing development link is:

```text
~/.config/omarchy/plugins/pym.droidlink → /home/me/Projects/droidlink
```

If the widget is not already in the bar, enable it with:

```bash
omarchy plugin enable pym.droidlink --section right
```

This repository preserves plugin ID `pym.droidlink` and the `Panel.qml` entry
point. It does not modify packaged Omarchy files or Omarchy's configuration:
every option is on the popup's **Settings** page and saved in DroidLink's own
`~/.config/omarchy/droidlink.ini`, under `[preferences]` and `[autoConnect]`.
Settings from 0.7.0 kept in `shell.json` are no longer read; set them again on
the Settings page (the defaults are unchanged). Omarchy watches the user plugin directory for updates.

Before each launch, DroidLink registers a named Hyprland window rule with
`hyprctl eval`. The rule sends its diagnostic terminal straight to the hidden
`special:droidlink` workspace without focusing it, so the scrcpy video window is
the only one you see. No Hyprland config edit is needed. Without `hyprctl` the
terminal stays visible.

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
4. Select **Pair**. DroidLink then connects to the connection port Android
   advertises for the same host. If that service isn't known yet, it waits for
   one discovery refresh before asking you to connect manually. Direct Pair on
   an advertised pairing service and the fully manual Pair and Connect forms
   remain available in Wireless.

Pairing codes are passed on stdin, cleared after submission or dismissal, and
never saved in profiles or included in command arguments. Pairing grants ADB
trust; disconnecting does not forget that trust. Forget the host on Android to
revoke it. The plugin issues connection commands only on explicit clicks;
ADB itself may automatically connect to previously trusted mDNS services.

Discovery recognizes `_adb._tcp`, `_adb-tls-connect._tcp`, and
`_adb-tls-pairing._tcp`. Android runs one wireless ADB endpoint per host, so a
connection service on the host of a wireless device is merged into that device even
when the ports differ: a ready device keeps the port ADB is using (Avahi can briefly
hold a stale one), and an offline device takes the newly advertised port, so its
Connect button reconnects after Wireless debugging is toggled. Offline entries ADB
keeps for a host that is ready again on another port are hidden. USB and Wi-Fi
remain separate transports, and pairing ports remain distinct. mDNS does not supply a reliable hardware serial or model name,
so unconnected entries explicitly show a service identity instead.

The plugin invokes `bash discover-mdns.sh` using its resolved plugin path. The
script keeps one `avahi-browse` open per Android service type while the popup is
open, and stops them when it closes. Resolved records and removals stream to the
plugin as Avahi sees them, so devices appear and leave without a rescan; the
plugin decodes names, shows one row per service (IPv4 preferred), and adds interface scopes to
link-local IPv6 addresses. Pairing and connection ports remain distinct. On
opening, the previous results stay shown for 1.5 seconds while the browsers
catch up, so the list doesn't flicker. If any browser stops, the error is shown
and the browsers are restarted after 10 seconds.

This path does not invoke `adb mdns services` and works independently of ADB's
mDNS build support. If Avahi is missing or its daemon is unavailable, the popup
reports the error and keeps USB and manual wireless controls available. The
script does not start or configure the daemon. Some networks block multicast.
No automatic ADB server restart, package installation, or broad disconnect is
performed. Wireless debugging and TCP mode are only switched on by an explicit
**Go wireless**.

### Pair with a QR code

On Android 11 or later, open Wireless, choose **Show QR code**, then on Android
open Developer options › Wireless debugging › **Pair device with QR code** and
scan it. Nothing needs to be typed or installed on the phone.

`qr-pair.sh` makes a one-time service name (`droidlink-` and 8 random
characters) and a 16-character password from `/dev/urandom`, and encodes
`WIFI:T:ADB;S:<name>;P:<password>;;`, the payload Android Studio uses. The
payload reaches `qrencode` on stdin, never in a process's arguments. Once
scanned, Android announces `_adb-tls-pairing._tcp` under that name; DroidLink
waits for that exact service, so another device's pairing service is never
used, then runs `adb pair` with the password on stdin and connects as after
code pairing. The code is held in memory only while it is shown, and is
dropped when you cancel, leave Wireless, or close the popup (wireless
discovery stops with the popup, so it could no longer pair). Showing a code
needs wireless discovery; the button is disabled while Avahi is unavailable.

### Go wireless

A ready USB device has **Go wireless**. With the cable still in, `go-wireless.sh`:

1. Reads the device's Wi-Fi IPv4 address (`wlan*`; mobile data doesn't count).
2. On Android 11+, turns on Wireless debugging (`settings put global
   adb_wifi_enabled 1`), waits for the port adbd publishes in
   `service.adb.tls.port`, and connects to it. A host already trusted over USB
   is usually accepted without pairing. If it isn't, DroidLink says so and
   points to **Pair with QR code**. If Android asks whether to allow wireless
   debugging on this network, allow it.
3. On Android 10 and older, runs `adb tcpip 5555` and connects to port 5555.
   That mode is unencrypted and ends when the device reboots.

It then waits for the wireless transport to be ready and tells you to unplug
the cable. Wireless debugging stays on afterwards; turn it off on Android when
you're done.

### Auto-connect

Turn on **Auto-connect paired devices** on the popup's Settings page. It is
saved in DroidLink's own `droidlink.ini` (`[autoConnect] enabled`). Then, when a device that was connected here before turns on
Wireless debugging (the Quick Settings developer tile is quickest), DroidLink
connects it without a click, even with the popup closed.

- A device is remembered once it is ready over Wi-Fi here, however it got
  connected (QR pairing, Go wireless, Connect), by its Wireless debugging
  service name minus the random suffix (`adb-<serial>`). Up to 50 are kept in
  `droidlink.ini` under `[autoConnect]`, and remembering happens whether or
  not the setting is on.
- Each announced endpoint gets one `adb connect`. A device that refuses this
  computer (unpaired on Android) is forgotten until it connects again; a
  network failure waits for the next announcement. Toggling Wireless debugging
  announces a new port, which is tried once.
- Devices that were never connected here are never contacted.
- The Avahi browsers keep running while the setting is on, even with the popup
  closed. Device details are still only read while the popup is open.

## Mirroring and profiles

| Profile | Maximum edge | FPS | Codec | Video bitrate | Audio |
| --- | --- | --- | --- | --- | --- |
| Balanced | 1920 px (1080p on a 16:9 display) | 60 | H.264 | 8 Mbps | On |
| Low bandwidth | 720 px | 30 | H.264 | 4 Mbps | Off |
| High quality | Native | 60 | H.265 | 20 Mbps | On |

Resolution is the longest-edge limit, preserving aspect ratio; it is not a fixed
width × height. The menu includes 3840 px (4K on a 16:9 display) and 60 Mbps.
Native resolution and unlimited FPS omit those limits. The chosen FPS and bitrate
are passed to scrcpy with the same flags for USB and wireless ADB serials. Actual
quality, FPS, and encoders depend on the phone and network. Audio forwarding requires Android 11+;
Android 11 should be unlocked at launch. Unsupported audio may fall back to video
only. See the [upstream audio guide](https://github.com/Genymobile/scrcpy/blob/master/doc/audio.md).

Edit the options and save them with a custom name (up to 30 profiles). Saving under an
existing custom name asks you to press **Replace**, and **Remove** asks you to
**Confirm**; either request lapses after 5 seconds. Built-in profiles cannot be overwritten. Saved
profiles, the last selected profile, and recording folder persist in
`$XDG_CONFIG_HOME/omarchy/droidlink.ini` (normally
`~/.config/omarchy/droidlink.ini`). Unsaved changes last until the widget reloads.
**Reset** restores edited options from the profile selected before those edits. It
does not modify Omarchy settings, saved profiles, the recording folder, or any
device connection.

### Phone screen and orientation

During a video session, **Phone screen on** lights the physical display for
passwords or fingerprint authentication; **Phone screen off** darkens it again
without restarting the session or interrupting its recording. The buttons send
scrcpy's Alt+Shift+O / Alt+O shortcuts to the owned scrcpy process through
Hyprland's Lua dispatcher. They do not target the focused window. Dispatch
acknowledgement is reported as a request, not as verified phone display state.
If dispatch fails, use those shortcuts directly in the scrcpy window.

The four orientation buttons use `adb shell wm user-rotation lock` with Android's
four rotation values. Each one disables auto-rotate and locks the device to the
chosen orientation. **Auto rotate / reset** uses `adb shell wm user-rotation free`
to release the lock and restore sensor-based rotation. `session.sh rotate` runs
these commands against the active session's device and does not restart scrcpy.

When the controls appear, including after an Omarchy shell restart, they read
`settings get system accelerometer_rotation` and `user_rotation` to show the
phone's current lock. DroidLink records a lock it set under
`$XDG_RUNTIME_DIR/droidlink-$UID/rotation` and sends `wm user-rotation free`
when that session ends, whether it was stopped, its window was closed, or
scrcpy exited. **Auto rotate / reset** clears that record. A lock chosen on the
phone is reported as such and left in place.

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
create `.mka` files. A missing or read-only folder stops the launch with a
message saying so. The session displays its exact path. Audio is included only
when forwarding is enabled and supported.
Use **Stop mirroring** or close the scrcpy window to finalize a recording.
Scrcpy runs in Omarchy's configured default terminal on a hidden
`special:droidlink` workspace, leaving only the scrcpy video window visible.
Press **Show log** on the Mirror page (or run
`hyprctl dispatch 'hl.dsp.workspace.toggle_special("droidlink")'`) to show or hide its
diagnostic terminal. The terminal is asked to stay open after scrcpy exits if
the configured terminal supports that option. Closing the popup, switching
tabs, or restarting the Omarchy shell leaves the session running. Every monitor's
widget reads the same session state and can stop it; only one DroidLink session
runs at a time. Nothing polls the session: widgets watch its state file, and
while a session runs `session.sh wait` sleeps on the scrcpy process (util-linux
`waitpid`) and ends the session, releasing a rotation lock DroidLink set, as soon
as scrcpy exits, even with the popup closed. Closing the terminal also ends the session. A vanished device
selection is never silently replaced by another phone.

All external programs use argument arrays, not shell interpolation. Session state
lives under `$XDG_RUNTIME_DIR/droidlink-$UID` and is checked against the process
start time so a stale PID is ignored. Stop sends `TERM` to scrcpy so it can close
streams and finalize recordings, then force-kills only a session that fails to exit.
Discovery and ADB actions have bounded timeouts; their diagnostics are bounded and
shown in the popup. A wireless device that is still advertised but doesn't answer
(asleep, or Wireless debugging off) gets one muted hint; hard failures such as a
stopped `avahi-daemon` are shown as errors. Hover the message for Avahi's full
output. Scrcpy diagnostics remain in the hidden terminal while it is
open. ADB's failure messages are checked even when it exits with code 0.

## Keep awake and unlock

**Keep awake** keeps the screen on without mirroring, also on battery (scrcpy's
`--stay-awake` only works while charging). It wakes the device, then runs a
window-less `scrcpy --no-video --no-audio --no-window --keep-active` in its own
session. scrcpy changes no Android setting, so nothing is left behind if
DroidLink or the shell stops; turning it off stops that process. The choice is
remembered per device and the keeper restarts when the device reconnects,
including on a new wireless port.

**Unlock PIN…** stores the device's PIN or password in the desktop keyring with
`secret-tool` (libsecret: gnome-keyring, KWallet, …), never in DroidLink's
settings, logs or command arguments. It is keyed by the device's hardware serial
(`ro.serialno`) as reported live, never by its adb address, so a different
device on a reused address can't receive it. Unlocking:

1. wakes the device and does nothing more if no lock screen is showing;
2. opens the bouncer (`wm dismiss-keyguard`) and types only once a PIN or
   password field is on screen (`uiautomator`), so a pattern lock or a missing
   bouncer costs no attempt;
3. types the secret through `adb shell` stdin and presses Enter, **once**. If the
   lock screen is still showing, unlocking is paused for that device until the
   secret is saved again, so a wrong or outdated PIN never runs into Android's
   lockout or wipe limits.

Passwords may use printable ASCII (4–64 characters, inner spaces allowed);
`input text` can't type accents or emoji, so those are refused when saving.
Pattern locks aren't supported. While it is typed, the secret is briefly visible
to processes on the device itself, which anything with adb access controls
anyway.

The Settings page chooses when this happens: **Wake on mirror launch** (on by
default), **Unlock on mirror launch**, **Wake on connect** and **Unlock on
connect** (off). A device without a saved PIN is only woken. Devices already
connected when the shell starts are not woken or unlocked; only their keepers
return. A failed wake or unlock is reported and never blocks the mirror launch.
Preferences live under `$XDG_STATE_HOME/droidlink/devices` (marker files, no
secrets); keepers are tracked under `$XDG_RUNTIME_DIR/droidlink-$UID/keepers`.

## Development

Validate the plugin:

```bash
omarchy plugin validate /home/me/Projects/droidlink
node tests/model.test.cjs
node tests/mdns.test.cjs
node tests/screen-power.test.cjs
node tests/screen-rotation.test.cjs
node tests/profiles.test.cjs
node tests/device-power.test.cjs
node tests/pairing.test.cjs
node tests/auto-connect.test.cjs
bash tests/session.sh
bash tests/device-power.sh
bash tests/go-wireless.sh
bash tests/shared-discovery.sh
DROIDLINK_TEST_CASE=avahi_unavailable bash tests/shared-discovery.sh
DROIDLINK_TEST_CASE=no_track bash tests/shared-discovery.sh
bash tests/smoke.sh
DROIDLINK_TEST_CASE=avahi_unavailable bash tests/smoke.sh
```

All Node suites run offline (`node --test tests/*.test.cjs`); the shell-helper suite uses a fake Avahi command
and covers streamed removals, a browser that stops, and that no browser outlives the helper.
Ask before running live discovery or desktop tests in an active user session.
Screen-power tests execute the command builder and QML method bodies with fake
commands/timers; they do not exercise QML bindings or deliver real compositor
shortcuts. Physical authentication, screen-power changes, and idle behavior still
require an approved real-device test.

The device-power test runs `device-power.sh` against a fake keyring and a
simulated lock screen: odd passwords (quotes, spaces, `%s`, `$`, backticks) are
typed exactly, the secret never appears in any argv, another device never gets
it, a pattern lock costs no attempt, a wrong secret is tried once then paused,
and one keeper runs per device and returns on connect.

The go-wireless test runs `go-wireless.sh` against a fake adb that simulates
Wireless debugging: Android 11+ connects over TLS and never switches to TCP,
an already-enabled device is left alone, a stale port is skipped, Android 10
falls back to `adb tcpip`, mobile data alone is refused, and an untrusted host
is pointed to QR pairing. The pairing test runs `qr-pair.sh` against a fake
qrencode and checks the payload format, that the password stays out of argv,
and that each code is new; the smoke test checks that a shown code pairs only
once its own service is announced, and that auto-connect remembers ready
phones, reconnects a trusted one, forgets one that refuses, and tries each
endpoint once.

The session test launches a fake scrcpy through a fake terminal and verifies shared
state, duplicate-launch rejection, argument preservation, and stop. The
shared-discovery test creates two widget consumers of one injected service and
uses fake ADB/Avahi executables to prove one tracker serves every consumer, queued
refreshes never overlap, a refresh that finds nothing new keeps the same rows, and a
failing tracker (`no_track`) falls back to polling. The smoke test runs headlessly with an isolated QML shell, temporary settings,
and fake ADB/Avahi/scrcpy/Omarchy terminal executables. It checks
discovery/merging, stdin pairing, connect/disconnect, failure reporting, timeouts,
missing executables, profile persistence, launch options, cross-panel session visibility,
graceful stop, and stale selection handling without touching real devices or the bar configuration.
Temporary test files are removed on exit.

For a visual review, create a temporary directory and run
`DROIDLINK_PREVIEW_DIR=/absolute/path/to/that/directory bash tests/smoke.sh`.
This briefly opens a separate preview window with fake devices, captures its three tabs,
and exits. Preview requires the QtTest QML module.

The original implementation milestones were validated in order: read-only USB/mDNS popup,
connection controls, then scrcpy profiles. Manifest validation only checks the
manifest and file layout; the QML and fixture tests exercise runtime behavior.
The host's ADB reports `mdns is not supported by this version of adb`, so the
separate Avahi discovery script replaces that discovery path. On the desktop,
with a Galaxy Tab S11 (Android 16) over wireless ADB, the following were checked
by hand: live Avahi discovery, device names, the session card, rotation-lock
release after the scrcpy window closes, and the recording-folder check. Other
devices, pairing flows, and recording media have not been checked on hardware.
Fixture tests do not establish hardware compatibility.

Discovery output: [Avahi browser implementation](https://github.com/avahi/avahi/blob/master/avahi-utils/avahi-browse.c).
Protocol references: [ADB Wi-Fi architecture](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md)
and [scrcpy video options](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md).
