# Changelog

## 1.1.0 — 2026-10-31

### Added

- **App names without a launcher icon:** apps scrcpy doesn't name (a
  keyboard, for example) showed their package name in Sound's Apps list; their
  label is now read once from the app's APK in the background and cached.
  While it is read, the row shows a spinning "reading name".

### Fixed

- **Wrong app names in Sound:** after a factory reset (or an app reinstall)
  the Apps list could name a player after whatever app held its uid before,
  e.g. a game shown as another app. Names now follow the package the device
  reports for the uid on every read, and a player whose package isn't in the
  cached app list rebuilds it. System players no longer rebuild that list
  every 10 minutes.
- **Sound sliders jumping:** when an app came, went or got its name, every
  Apps slider was rebuilt and replayed its fill from 0. Rows are now moved in
  place, so only a new row is created.
- **Sound rows one read late:** a new app in Sound's Apps list appeared one
  read (2 s) after the status that listed it.

## 1.0.2 — 2026-10-24

### Fixed

- **IPv6 wireless devices:** a device listed by its link-local endpoint
  (`[fe80::…%eno1]:39977`) no longer fails with "Unexpected adb serial";
  the serial check now accepts `[`, `]` and `%`.
- **Duplicate wireless device:** a device adb holds over both IPv4 and IPv6
  (adb's own mDNS auto-connect can pick the link-local address) is one row;
  Disconnect drops both links. Auto-connect also no longer opens a second
  link when the IPv6 mDNS record resolves before the IPv4 one.

### Docs

- README: now a short landing page (pitch, quick start, features, install,
  remove, security, requirements). The user manual moved unchanged into
  `docs/guide/`, one page per feature area (features, requirements,
  connecting, mirroring, webcam, keep awake and unlock, sound, send text),
  indexed in `docs/README.md`. What each test suite covers moved to the
  development runbook.

## 1.0.1 — 2026-10-21

### Fixed

- **Runtime folder:** session, keep-awake and webcam preview state is refused
  when its folder is a symlink or owned by another user. Without
  `XDG_RUNTIME_DIR` that folder falls back to the shared `/tmp`.
- **Sound:** the phone's installed-app list, its playing apps and their
  volumes no longer appear in process arguments; they reach awk as files and
  the environment. `~/.cache/omadroid` is now owner-only (folders 700, files
  600), and an older readable cache is tightened the next time Sound opens.
- **Settings:** `omadroid.ini`, which holds remembered device ids and the
  last device's address, is made owner-only (600) at startup, also when an
  older version left it readable.
- **Duplicate devices:** a device that adb reaches both by `host:port` and
  by its mDNS name (adb's own auto-connect) shows as one row, not two.
  Disconnect on its page drops both links, so it doesn't stay connected.
- **Send text:** typed and pasted text no longer appears in process
  arguments, where other local users could read it. It reaches
  `send-text.sh` and then `adb shell` on stdin, as the unlock PIN already
  did.

### Docs

- README: a **Remove** section and a **Security and privileges** section that
  list everything OmaDroid installs, writes or runs as root. The full privilege
  model moved to `SECURITY.md`, with private vulnerability reporting; the
  README keeps a short summary and links it.
- `CONTRIBUTING.md` and a documentation index in `docs/README.md`, linked
  from the README and `AGENTS.md`.
- Specs in `docs/specs/`: the `omadroid.ini` keys, the `OMADROID_*`
  environment variables, the shell integration (entry points, discovery
  service, Send text overlay and hotkey block) and the output of each script
  that QML parses.
- Runbooks: `docs/runbooks/development.md` (setup, tests, offscreen previews,
  refreshing the README hero, releases) and
  `docs/runbooks/troubleshooting.md` (messages, causes and fixes).
- Brand sources: `docs/branding.md` with the hero's colours, wordmarks in
  `docs/brand/logo.svg` and `logo-light.svg`, and `docs/brand/preview.svg`,
  an editable layout of the README hero built on offscreen captures with fake
  devices. `preview.png` is unchanged.

### Tests

- GitHub Actions runs the test suites on every push and pull request.
  `OMADROID_SKIP_QML=1 bash tests/run-all.sh` skips the two suites that need
  quickshell and the Omarchy shell and ends with `OMADROID_PARTIAL_OK`, so a
  partial run never reads as a full pass.
- Pull request and issue templates.

## 1.0.0 — 2026-10-18

The first public release, as OmaDroid (`pym.omadroid`).

### Added

- **OmaDroid name and icon:** an Android head over a terminal prompt, in the
  bar.
- **Device-centric popup:** a device list grouped into CONNECTED, NEEDS
  ATTENTION and NEARBY, with one inline action per row (Reconnect, Connect,
  Pair). Each ready device has its own page: a hero with model, Android
  version, connection, battery, storage and memory; **Mirror**, **Audio** and
  **Webcam** session cards with live summaries and their options behind ⚙;
  one compact row of device controls (Wake/Unlock, Lock, Awake, Text, Wireless
  or Disconnect); and **Sound** and **Info** tabs.
- **+ Add device:** QR code, pairing code and manual address in one page.
- **Settings toggles** for Auto-connect, wake and unlock when a device
  connects or mirroring starts, the Send text hotkey and the scan interval.
- **Session banner** on every view: click it to open the session's device, ■
  to stop it.
- **One-click switching:** starting a session while another runs, of another
  kind or on another phone, stops it and starts the new one. A recording
  mirror asks first, ■ cancels a switch, and webcam **Apply** restarts on the
  same phone and output.
- **Automatic webcam preview:** a webcam started from the popup opens its live
  preview while the popup is open.
- **Unlock PIN bound to the device:** the saved PIN is tied to a sha256 of the
  device's `ro.serialno` and `android_id`, and unlock refuses, without spending
  its one attempt, when the identity differs.
- **Fix a PIN where the warning shows:** a PIN that can't be used gets a
  **Save PIN…** button on the device page, and the control reads Wake until it
  is saved again.
- **Docs:** `docs/architecture.md`, Architecture Decision Records in
  `docs/adr/`, and agent instructions in `AGENTS.md`. Scripts live in
  `scripts/`.
- `tests/run-all.sh` runs every test suite and prints `OMADROID_ALL_OK`.

### Fixed

- Theme colours under Qt 6.12, whose own `Color` hid the theme's: the popup
  lost its colours.
- The Send text hotkey refuses a `bindings.lua` whose OmaDroid block has lost
  its end marker, instead of dropping the lines after it, and keeps only the 2
  newest backups.
- Device names are read for devices that turned ready while a name read was
  running.
- The Sound tab drops a status read that finished for another device.
- A session in a terminal other than foot gets 8 seconds to start scrcpy, so
  a slow terminal is no longer reported as a failed launch.
- The top-level scripts are executable.
