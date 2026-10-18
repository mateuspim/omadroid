# Changelog

## Unreleased

### Fixed

- **Runtime folder:** session, keep-awake and webcam preview state is refused
  when its folder is a symlink or owned by another user. Without
  `XDG_RUNTIME_DIR` that folder falls back to the shared `/tmp`.

### Docs

- README: a **Remove** section and a **Security and privileges** section that
  list everything OmaDroid installs, writes or runs as root.

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
