# Requirements and enabling

What OmaDroid needs, what each optional tool adds, and how it fits into Omarchy and Hyprland.

Install the ADB tools, scrcpy, and `qrencode` for QR pairing:

```bash
omarchy pkg add android-tools scrcpy qrencode
```

Requires Omarchy's Quickshell shell, Qt 6.5+, `adb`, Bash, `awk`, GNU coreutils
(`timeout`), util-linux (`flock`, `setsid`, `setpriv`, `waitpid`), Avahi
(`avahi-browse` and a running `avahi-daemon`), foot (preferred for the hidden
session terminal) or an Omarchy default terminal, and scrcpy 4.1+ for
mirroring, audio, the webcam and idle prevention. This implementation was
checked against the installed scrcpy 4.1 command-line options. The bar and
popup warn when `adb`, `scrcpy`, or a configured default terminal is missing.

Optional, each only for the feature named:

- `qrencode`: pairing with a QR code.
- `secret-tool` (libsecret): saving an unlock PIN.
- `v4l2loopback-dkms`: the Android webcam (see [Android webcam setup](webcam.md)); `ffmpeg` (with
  `ffprobe`): its in-panel preview; `wl-copy` (wl-clipboard): **Copy
  commands** and the Info tab's copy buttons; `fuser` (psmisc), when present,
  lets OmaDroid refuse an output another app is holding.
- Python 3 (standard library only): per-app volume and **Mute all** in the
  Sound tab.
- `jq`: closing the finished sessions' hidden terminals before a new launch.
- Node: development tests only; there are no npm packages.

To work on a local checkout, link it in place of the installed copy:

```text
~/.config/omarchy/plugins/pym.omadroid → /path/to/your/omadroid checkout
```

If the widget is not already in the bar, enable it with:

```bash
omarchy plugin enable pym.omadroid --section right
```

OmaDroid does not modify packaged Omarchy files or Omarchy's configuration:
every option is in the popup's **Settings** (⚙) and saved in OmaDroid's own
`~/.config/omarchy/omadroid.ini`, under `[preferences]` and `[autoConnect]`.
Omarchy watches the user plugin directory for updates.

Before each launch, OmaDroid registers a named Hyprland window rule with
`hyprctl eval`. The rule sends its diagnostic terminal straight to the hidden
`special:omadroid` workspace without focusing it, so the scrcpy video window is
the only one you see. No Hyprland config edit is needed. Without `hyprctl` the
terminal stays visible.
