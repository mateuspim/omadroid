# Troubleshooting

Symptom → cause → fix. Messages in quotes are what OmaDroid shows. For more
detail, read the shell log (read-only):

```bash
quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i omadroid
```

A running session's scrcpy output is behind **Log** on its session card.

## Setup

| Symptom | Cause | Fix |
| --- | --- | --- |
| The bar icon is in the urgent colour; the popup lists missing tools | `session.sh check` didn't find `adb`, `scrcpy`, or foot / an Omarchy default terminal | `omarchy pkg add android-tools scrcpy` (and `foot`, or set a default terminal). The check runs again when the popup opens. |
| "Runtime folder '…' must be a directory owned by …, not a symlink; refusing to use it." | `$XDG_RUNTIME_DIR` is unset, so the folder fell back to the shared `/tmp`, and that name is a symlink or another user's | Log in through a session that sets `XDG_RUNTIME_DIR`, or remove the stray `/tmp/omadroid-<uid>` if it is yours. |
| The scrcpy terminal shows up instead of staying hidden | `hyprctl` isn't available, so the window rule wasn't registered | Run inside Hyprland; nothing else is needed. |

## Finding and connecting devices

| Symptom | Cause | Fix |
| --- | --- | --- |
| "OmaDroid mDNS: missing avahi-browse. Install Avahi." | Avahi tools are not installed | Install Avahi. USB and the manual **Address** form still work. |
| "OmaDroid mDNS: discovery stopped (… exited with …). Check that avahi-daemon is running." | `avahi-daemon` isn't running; OmaDroid never starts it | Start it (`sudo systemctl enable --now avahi-daemon`). The browsers retry after 10 s. |
| No wireless devices appear although Wireless debugging is on | The network blocks multicast, or the phone is on another network | Put both on the same network, or use **+ Add device** › address / pairing code. |
| "… was seen but didn't answer. Wake it and check Wireless debugging is on." | The phone announced itself but didn't resolve in time (often asleep) | Wake it, keep Wireless debugging on, refresh (F5). |
| A USB row under NEEDS ATTENTION says "Accept the USB debugging prompt" | The device hasn't authorized this computer | Unlock the phone and accept the prompt. |
| Connect fails on a NEARBY device | This computer isn't paired with it | OmaDroid opens **Pairing code**; or use **QR code** in **+ Add device**. |
| A remembered device no longer auto-connects | It refused this computer (unpaired on Android), so it was forgotten | Pair again; it is remembered once it is ready over Wi-Fi. |
| **QR code** is disabled | Wireless discovery (Avahi) is unavailable | Fix Avahi as above. |

## Go wireless

| Message | Fix |
| --- | --- |
| "… isn't on Wi-Fi. Join the same network as this computer, then try again." | Mobile data doesn't count; join Wi-Fi. |
| "Wireless debugging didn't start on …" | Allow wireless debugging on this network if Android asks, then retry. |
| "Couldn't authenticate to …" / "… connected but isn't authorized." | Pair with **+ Add device** › **QR code**. |

## Sessions (Mirror, Audio, Webcam)

| Symptom | Cause | Fix |
| --- | --- | --- |
| "The OmaDroid terminal did not start scrcpy. Check foot or your default terminal." | The terminal didn't reach scrcpy within 3 s (foot) or 8 s (others) | Install foot, or check that the default terminal starts. |
| "An OmaDroid session is already active." / "… already starting." | One session runs per machine ([ADR 2](../adr/0002-one-scrcpy-session-per-machine.md)) | Stop it with ■ on the banner, or start the new one from its card, which switches. |
| "Recording folder … does not exist." / "… is not writable." | The profile records into a missing or read-only folder | Choose another folder under the Mirror options. |
| "Screen control failed …" | Hyprland didn't acknowledge the key sent to the scrcpy window | In the scrcpy window use Alt+Shift+O (screen on) or Alt+O (off). |

## Webcam

| Symptom | Cause | Fix |
| --- | --- | --- |
| Card reads "Needs setup": "Virtual camera driver missing" | `v4l2loopback-dkms` isn't installed | **Set up webcam** (a visible terminal asks for your password), or **Copy commands**. |
| "Virtual camera is off" | Driver installed, module not loaded | **Enable output**. |
| "Driver needs a build" | No module for the running kernel | Check the DKMS build and matching kernel headers, then reboot. |
| "No virtual camera output" | The module is loaded but no output is visible | Check `ls -l /dev/video*` and its permissions. |
| "Camera capture requires Android 12+; … reports SDK …" | scrcpy camera capture needs Android 12 | Use a newer device. |
| "/dev/videoN is occupied. Close OBS, your video call, or the app using it, then retry." | Another app holds the output | Close it, then start the webcam. |
| "Cannot write to /dev/videoN. Check its video group permissions." | The device node isn't writable for you | Fix the node's group or permissions. |
| "This camera does not support the chosen size." | The camera refused the resolution | Select Automatic or another quality; check **Log**. |
| Preview says apps get one size while scrcpy writes another; video is garbled | An app kept the format from an earlier session | Close every app using the output, then stop and start the webcam. |

## Keep awake and unlock

| Message | Fix |
| --- | --- |
| "Unlock is paused after a failed try." | Unlock the device by hand, then **Save PIN…** again. |
| "This device's identity doesn't match the one the PIN was saved for …" | After a factory reset of the same device, save the PIN again. A different device never gets the PIN. |
| "The unlock PIN was saved without this device's identity." | Save the PIN again. |
| "This device uses a pattern lock, which OmaDroid can't enter." | Pattern locks aren't supported; use a PIN or password. |
| "secret-tool (libsecret) isn't installed …" / "The desktop keyring refused the PIN." | Install libsecret and run an unlocked keyring (gnome-keyring, KWallet). |
| "Use 4-64 plain ASCII characters …" | Accents and emoji can't be typed over adb. |

## Sound

| Symptom | Cause | Fix |
| --- | --- | --- |
| Apps only have a mute toggle, no slider | Not a Samsung device, or the per-firmware audio codes didn't verify | Expected: other phones can only mute an app. |
| **Mute all** and per-app volume are missing | Codes couldn't be read or verified, or `python3` is missing | Install Python 3. Codes that don't verify are never used ([ADR 6](../adr/0006-audio-codes-from-framework-jar.md)). |
| The first Sound read takes several seconds | The device's `framework.jar` (about 50 MB) is copied once per firmware | Wait; later reads use the cache in `~/.cache/omadroid`. |

## Send text

| Symptom | Fix |
| --- | --- |
| "COMBO is already bound to …. Pick another combination." | Choose another key combination on the Settings page. |
| "… has the line '-- >>> OmaDroid send text …' without '-- <<< OmaDroid send text' after it." | Restore or delete OmaDroid's block in `bindings.lua` by hand; nothing was changed. |
| Key combinations like `ctrl+a` do nothing | They need Android 13+ (`input keycombination`). |
| Accented characters aren't typed | `adb shell input text` can only type ASCII. |
