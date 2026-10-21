# Development runbook

## Set up a checkout

OmaDroid is plain QML, JavaScript and bash: there is nothing to build and no
npm packages. You need the runtime [requirements](../guide/requirements.md)
plus, for the tests, Node (any current LTS), Python 3, ripgrep (`rg`) and
Omarchy's Quickshell shell (`/usr/share/omarchy/shell`) for the QML suites.

1. Clone the repository on branch `master`.
2. Link the checkout in place of the installed copy (move an installed copy
   aside first):

   ```bash
   ln -s /path/to/omadroid ~/.config/omarchy/plugins/pym.omadroid
   ```

3. Enable the widget if it is not in the bar yet:

   ```bash
   omarchy plugin enable pym.omadroid --section right
   ```

Omarchy watches the plugin directory and reloads changed QML. Read the live
shell log without restarting anything:

```bash
quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i omadroid
```

Don't restart the shell (`omarchy-restart-shell`) or run live device tests in
someone's session without asking them.

## Run the tests

```bash
omarchy plugin validate .
bash tests/run-all.sh
```

`tests/run-all.sh` runs the Node suites (`node --test tests/*.test.cjs`), then
each shell suite, including the `OMADROID_TEST_CASE` variants
(`shared-discovery.sh no_track`, `smoke.sh avahi_unavailable`). It stops at the
first failure, naming it, and prints `OMADROID_ALL_OK` when everything passed.
A new shell suite must be added to its list, or the run fails. Run one suite
on its own with, for example, `bash tests/session.sh` or
`OMADROID_TEST_CASE=avahi_unavailable bash tests/smoke.sh`. The user-facing
scripts in `scripts/` are executable and can be run directly.

Every suite runs against named fakes (`tests/mock-*.sh`) in a temporary
directory with isolated XDG folders: no real device, keyring, Hyprland config
or user settings is touched. The QML suites (`shared-discovery.sh`,
`smoke.sh`) run `quickshell` with `QT_QPA_PLATFORM=offscreen`, so no window
opens.

CI ([`.github/workflows/test.yml`](../../.github/workflows/test.yml)) runs
`OMADROID_SKIP_QML=1 bash tests/run-all.sh` on Ubuntu: everything except the
two QML suites, which need quickshell and an installed Omarchy shell. That run
ends with `OMADROID_PARTIAL_OK`; run the full command locally before a
release.

[What the suites cover](#what-the-suites-cover) describes each suite;
[specs](../specs/) hold the contracts the tests check.

## What the suites cover

All Node suites run offline; the shell-helper suite uses a fake Avahi command
and covers streamed removals, a browser that stops, and that no browser outlives the helper.
Ask before running live discovery or desktop tests in an active user session.
Screen-power tests execute the command builder and QML method bodies with fake
commands/timers; they do not exercise QML bindings or deliver real compositor
shortcuts. Physical authentication, screen-power changes, and idle behavior still
require an approved real-device test.

The device-power test runs `scripts/device-power.sh` against a fake keyring and a
simulated lock screen: odd passwords (quotes, spaces, `%s`, `$`, backticks) are
typed exactly, the secret never appears in any argv, a device with another
serial or `android_id` never gets it (and the refusal keeps the attempt), the
raw `android_id` is never stored, a pattern lock costs no attempt, a wrong secret is tried once then paused,
Lock reports an instant lock, a lock delay and an ignored sleep key, and one keeper runs per device and returns on connect.

The go-wireless test runs `scripts/go-wireless.sh` against a fake adb that simulates
Wireless debugging: Android 11+ connects over TLS and never switches to TCP,
an already-enabled device is left alone, a stale port is skipped, Android 10
falls back to `adb tcpip`, mobile data alone is refused, and an untrusted host
is pointed to QR pairing. The pairing test runs `scripts/qr-pair.sh` against a fake
qrencode and checks the payload format, that the password stays out of argv,
and that each code is new; the smoke test checks that a shown code pairs only
once its own service is announced, and that auto-connect remembers ready
phones, reconnects a trusted one, forgets one that refuses, and tries each
endpoint once.

The audio-codes test builds fixture dex files (`tests/make-audio-dex.py`):
the Tab S11's codes, a phone without Samsung's app volume, payload-free
statics before the codes, an overloaded method and a table with a gap; the
last two must be refused. The device-volume test runs `scripts/device-volume.sh`
against a fake device (`tests/mock-volume-adb.sh`) that evaluates its real
device scripts: framework.jar is copied once per firmware, app names once,
only known codes are called, codes that don't verify are never used for a
read or a write, other phones fall back to app-op mute, and status still works
without python3.

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
`OMADROID_PREVIEW_DIR=/absolute/path/to/that/directory bash tests/smoke.sh`.
This renders the popup offscreen with fake devices, opens no window, writes one
PNG per view into that directory, and exits. `OMADROID_PREVIEW_PAGES` picks the
views, comma-separated and in order (`home`, `add`, `settings`,
`device` or `device-<part>` for the USB phone, `wifi` or `wifi-<part>` for the
wireless one, where the part is a tab (`sound`, `info`) or a session card whose
options are open (`mirror`, `audio`, `webcam`), plus session steps such as
`click-<kind>`, `start`, `record` and `stopped`; see `tests/Preview.qml` for
the full list and default). `OMADROID_PREVIEW_QML`
swaps in another capture script: `tests/HomePreview.qml` captures the device
list, header and session banner, and `tests/DevicePreview.qml` captures a
device page per device and section. Preview requires the QtTest QML module.

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

## Offscreen previews

To look at a view without opening a window, render it offscreen with the fake
devices:

```bash
dir="$(mktemp -d)"
OMADROID_PREVIEW_DIR="$dir" bash tests/smoke.sh
```

This writes one PNG per view into `$dir` (an absolute path outside the
checkout) and exits.

- `OMADROID_PREVIEW_PAGES` picks the views, comma-separated and in order:
  `home`, `add`, `settings`, `device` or `device-<part>` for the USB phone,
  `wifi` or `wifi-<part>` for the wireless one (part: `sound`, `info`, or
  `mirror` / `audio` / `webcam` with that card's options open), plus session
  steps such as `click-<kind>`, `start`, `record` and `stopped`. The full list
  is in `tests/Preview.qml`.
- `OMADROID_PREVIEW_QML=tests/HomePreview.qml` or `tests/DevicePreview.qml`
  swaps the capture script.
- `QT_SCALE_FACTOR=2` renders at twice the size (920 × 1800 px).
- Offscreen renders skip `MultiEffect`, and the popup uses the active Omarchy
  theme's colours.

Afterwards make sure nothing is left running, and kill your own leftovers:

```bash
pgrep -af omadroid-smoke
```

Never screenshot the desktop or inject input on the user's monitors for a
review. See [ADR 8](../adr/0008-offscreen-preview-harness.md).

## Refresh the preview

The README hero is [`preview.png`](../../preview.png) (3840 × 2160). Its
editable source is [`docs/brand/preview.svg`](../brand/preview.svg), which
places two offscreen captures from `docs/brand/captures/`. See
[branding](../branding.md) for colours and for how the SVG relates to the
shipped PNG.

1. Render the captures at 2× with the fake devices:

   ```bash
   dir="$(mktemp -d)"
   QT_SCALE_FACTOR=2 OMADROID_PREVIEW_PAGES=home,device-mirror \
     OMADROID_PREVIEW_DIR="$dir" bash tests/smoke.sh
   pgrep -af omadroid-smoke
   ```

2. Crop them to the part the hero shows and strip metadata:

   ```bash
   magick "$dir/0-home.png" -crop 920x1015+0+0 +repage -strip docs/brand/captures/home.png
   magick "$dir/1-device-mirror.png" -crop 920x1250+0+0 +repage -strip docs/brand/captures/device-mirror.png
   ```

3. Look at both captures: only fixture names (`Desk phone`, `Pixel 9`,
   `adb-NEW-…`, `USB123`) and fixture addresses may appear.
4. Render the hero from the repository root and look at the PNG before
   committing it:

   ```bash
   rsvg-convert -o preview.png docs/brand/preview.svg
   ```

The SVG asks for JetBrains Mono and falls back to DejaVu Sans Mono; a
different font changes text widths, so inspect the render. Keep the README's
alt text accurate when the panels change.

## Release

1. Bump `version` in `manifest.json` and turn `## Unreleased` in
   `CHANGELOG.md` into `## X.Y.Z — YYYY-MM-DD`.
2. Check the README and the [guide](../README.md#use-omadroid) cover the change.
3. `bash tests/run-all.sh` prints `OMADROID_ALL_OK`.
4. `omarchy plugin validate .` exits 0.
5. Commit `Release X.Y.Z`, then an annotated tag `vX.Y.Z`.
6. Ask the owner before pushing the commit or the tag, and before publishing a
   GitHub release.
