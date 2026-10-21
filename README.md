# <img src="icon.svg" alt="" width="32" height="32" align="top"> OmaDroid

![OmaDroid: the device list and a device page with the Mirror, Audio and Webcam session cards](preview.png)

**Android on your Omarchy desktop.** OmaDroid is a bar widget that finds your
phones and tablets over USB and Wi-Fi (ADB and mDNS), then mirrors them, plays
their audio or uses their camera as a webcam with
[scrcpy](https://github.com/Genymobile/scrcpy), all from one popup that follows
your Omarchy theme.

## Quick start

1. Install the tools and the plugin (see [Install](#install)):
   `omarchy pkg add android-tools scrcpy qrencode`, then
   `omarchy plugin add https://github.com/mateuspim/omadroid --enable`.
2. On Android, enable Developer options › USB debugging (or Wireless
   debugging), then plug in the cable and accept the prompt, or pair from
   **+ Add device** › **QR code**.
3. Click the OmaDroid icon in the bar and choose the device under
   **CONNECTED**.
4. Click **Mirror**, **Audio** or **Webcam** on its page. ⚙ on a card changes
   its options; ■ on the session banner stops the session.

## Features

- **One click per session:** Mirror, Audio or Webcam, each with a live summary
  of what a click starts. Starting another session switches to it.
  See [Features](docs/guide/features.md).
- **Devices:** USB and Wi-Fi devices show at once, grouped into **CONNECTED**,
  **NEEDS ATTENTION** and **NEARBY**, with battery, storage and Android
  details. See [Connecting a device](docs/guide/connecting.md).
- **Wireless without a cable:** pair with a QR code, a pairing code or an
  address. A USB device moves to Wi-Fi with one button, and auto-connect
  reconnects trusted devices. See [Pair with a QR code](docs/guide/connecting.md#pair-with-a-qr-code),
  [Go wireless](docs/guide/connecting.md#go-wireless) and
  [Auto-connect](docs/guide/connecting.md#auto-connect).
- **Mirroring and profiles:** resolution, FPS, codec, bitrate, recording,
  phone screen on/off and rotation. See
  [Mirroring and profiles](docs/guide/mirroring.md).
- **Android webcam:** the phone's camera as a V4L2 webcam for OBS or a call,
  with an in-panel preview. See [Android webcam setup](docs/guide/webcam.md).
- **Device controls:** wake, unlock with a PIN kept in your keyring, lock and
  keep awake. See [Keep awake and unlock](docs/guide/keep-awake-and-unlock.md).
- **Sound:** volume keys, mute all, ringer mode and per-app volume for apps
  playing sound. See [Sound](docs/guide/sound.md).
- **Send text:** a hotkey opens a prompt, and what you type there is typed on
  the device. See [Send text](docs/guide/send-text.md).

The popup follows your Omarchy theme and works from the keyboard (Tab, Enter,
F5, Escape).

## Install

```bash
omarchy pkg add android-tools scrcpy qrencode
omarchy plugin add https://github.com/mateuspim/omadroid --enable
```

`omarchy plugin update pym.omadroid` pulls new versions later.

## Remove

If you installed the Send text hotkey, remove it first: **Remove** in the
**Send text hotkey** row of Settings (⚙), or
`~/.config/omarchy/plugins/pym.omadroid/scripts/hotkey.sh remove`. This deletes only
OmaDroid's marked block in `~/.config/hypr/bindings.lua`. Then remove the
plugin:

```bash
omarchy plugin remove pym.omadroid
```

Removing the plugin leaves your settings and saved data on disk. To delete
them too:

```bash
rm -f ~/.config/omarchy/omadroid.ini     # settings and profiles
rm -rf ~/.local/state/omadroid           # per-device unlock state
rm -rf ~/.cache/omadroid                 # per-firmware audio codes
secret-tool clear app omadroid           # saved unlock PINs (keyring)
```

The webcam setup also installed a system driver. If no other app uses it, undo
it with:

```bash
sudo rm -f /etc/modules-load.d/v4l2loopback.conf /etc/modprobe.d/v4l2loopback.conf
omarchy pkg drop v4l2loopback-dkms
```

Recordings stay in the folder you chose, and the packages from
[Requirements](#requirements) stay installed.

## Security and privileges

OmaDroid runs as your user and never calls `sudo` on its own: only **Set up
webcam** opens a visible terminal that installs and loads `v4l2loopback`. Only
the Send text hotkey's **Install** writes outside the plugin; unlock PINs stay
in your keyring, and secrets travel on stdin, never in arguments or logs.
[SECURITY.md](SECURITY.md) lists every command OmaDroid runs and every file it
writes, and how to report a vulnerability.

## Requirements

- Omarchy's Quickshell shell (Qt 6.5+), `adb` (android-tools) and scrcpy 4.1+.
- Avahi with a running `avahi-daemon` for wireless discovery.
- Optional: `qrencode` (QR pairing), `secret-tool` (unlock PIN), Python 3
  (per-app volume), `v4l2loopback-dkms` and `ffmpeg` (webcam).

The full list, the webcam's driver setup and how OmaDroid fits into Hyprland
are in [Requirements and enabling](docs/guide/requirements.md) and
[Android webcam setup](docs/guide/webcam.md).

## Documentation

- [Documentation index](docs/README.md): the user guide, architecture,
  decisions, specs and runbooks.
- User guide: [features](docs/guide/features.md),
  [requirements](docs/guide/requirements.md),
  [connecting a device](docs/guide/connecting.md),
  [mirroring and profiles](docs/guide/mirroring.md),
  [webcam](docs/guide/webcam.md),
  [keep awake and unlock](docs/guide/keep-awake-and-unlock.md),
  [sound](docs/guide/sound.md) and [send text](docs/guide/send-text.md).
- [Troubleshooting](docs/runbooks/troubleshooting.md): messages, causes and
  fixes.
- [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and
  [CHANGELOG.md](CHANGELOG.md).

## Development

Link a checkout to `~/.config/omarchy/plugins/pym.omadroid`, then run
`omarchy plugin validate .` and `bash tests/run-all.sh` (prints
`OMADROID_ALL_OK`). The [development runbook](docs/runbooks/development.md)
covers setup, what each suite covers, offscreen previews and releases.

## License

MIT. See [LICENSE](LICENSE).
