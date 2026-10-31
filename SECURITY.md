# Security

## Reporting a vulnerability

Please report privately through GitHub's
[security advisories](https://github.com/mateuspim/omadroid/security/advisories/new)
rather than a public issue. Include the version (`manifest.json`), steps to
reproduce and impact, with device serials, names and addresses removed. You
can expect a reply within a week.

## Supported versions

Only the latest release on `master` receives fixes.

## Privilege model

Omarchy plugins run unsandboxed inside `omarchy-shell` as your user. OmaDroid
runs as your user too. Loading the plugin installs nothing, writes no config
outside its own settings, and never calls `sudo`.

- **Runs:** `adb` (discovery, connect, pair, `adb shell` for device
  controls, sound and Send text), `scrcpy` (mirror, audio, webcam, keep-awake
  keepers), `avahi-browse` (mDNS discovery), `secret-tool` (unlock PINs),
  `hyprctl` (hide the session terminal, screen-power keys to the scrcpy
  window), `qrencode` (QR pairing), `ffmpeg`/`ffprobe` (webcam preview),
  `wl-copy` (copy buttons) and foot or the Omarchy default terminal (session
  and setup terminals). Every call goes through `scripts/` or an argument
  array; QML never builds a shell string.
- **Root, once, when you ask:** **Set up webcam** (or **Enable output**) in a
  device's Webcam section opens a visible terminal running
  `scripts/webcam-setup.sh`. It runs `omarchy pkg add v4l2loopback-dkms`,
  `sudo modprobe v4l2loopback devices=1 exclusive_caps=1`, and writes
  `/etc/modules-load.d/v4l2loopback.conf` and
  `/etc/modprobe.d/v4l2loopback.conf` only if neither exists yet. The
  commands are fixed and take no input from the UI or the device; `sudo` asks
  for your password in that terminal. **Copy commands** copies the same
  commands if you'd rather run them yourself.
- **Packages:** the setup above is the only place OmaDroid installs a package.
  The other `omarchy pkg` lines in the README and the [guide](docs/README.md#use-omadroid) are
  for you to run.
- **Your config:** only the Send text hotkey's **Install** writes outside the
  plugin, as one marked block in `~/.config/hypr/bindings.lua` (keeping the
  2 newest backups); **Remove** deletes only that block. It refuses a file
  whose block has lost its end marker.
- **Secrets:** unlock PINs live in your keyring (libsecret), bound to a hash
  of the device's `ro.serialno` and `android_id`, and like pairing passwords
  are passed through stdin, never argv, logs or settings. Send text sends what
  you type or paste on stdin too. While a PIN is typed, it briefly appears in
  the arguments of the device's own `input` command, visible to processes on
  the device. See [ADR 4](docs/adr/0004-unlock-pin-in-keyring-bound-to-device.md).
- **Network:** OmaDroid talks only to the devices you pair or connect (adb,
  mDNS through Avahi). It downloads and executes nothing from the internet.
  Auto-connect, when you turn it on, connects only devices that were ready
  here before.
- **Runtime state:** session and keep-awake PIDs live in
  `$XDG_RUNTIME_DIR/omadroid-$UID`, owner-only. A folder that is a symlink or
  owned by another user is refused, and a recorded PID is trusted only if its
  process start time matches.
- **Cache:** `~/.cache/omadroid` holds each phone's installed-app names (for
  the Sound section), labels read from the APKs of apps without a launcher
  icon, and per-firmware audio codes. It is owner-only (folders 700, files
  600), and app lists and package names are handled as files or stdin, never
  as process arguments. An APK is copied to a private temporary folder only to
  read its label, then deleted; it is parsed, never installed or executed.
- **Settings:** `~/.config/omarchy/omadroid.ini` holds remembered device ids
  and the last device's address, so OmaDroid makes it owner-only (600) when it
  starts. It changes only that file's permissions, never its content.
- **State:** `~/.local/state/omadroid` holds per-device markers (keep-awake,
  the identity hash, a paused-unlock marker), never secrets.

It never changes configuration outside its own files on load. The README's
[Remove](README.md#remove) section lists how to delete everything it leaves.

## Limits

The device identity check keeps a saved PIN from a different device that turns
up on a reused address or advertises a copied serial. It is not a defence
against someone who already has adb access to your device: they can read the
same `android_id`, and they already control the device fully. ADB pairing
grants trust that disconnecting doesn't revoke; forget this computer on
Android to revoke it.
