# Keep awake and unlock

Keep a device awake without mirroring, lock it, and unlock it with a PIN kept in your keyring.

**Awake** (Keep awake) keeps the screen on without mirroring, also on battery (scrcpy's
`--stay-awake` only works while charging). It wakes the device, then runs a
window-less `scrcpy --no-video --no-audio --no-window --keep-active` in its own
session. scrcpy changes no Android setting, so nothing is left behind if
OmaDroid or the shell stops; turning it off stops that process. The choice is
remembered per device and the keeper restarts when the device reconnects,
including on a new wireless port.

**Lock** turns the screen off with `input keyevent KEYCODE_SLEEP`, the off half
of the power button, so it never wakes a screen that is already off. Android
locks at once when "Power button instantly locks" is on (its default); otherwise
the device page says the screen is off and the keyguard follows after the device's own
lock delay. A screen that stays on is reported as an error.

**Set…** (or **Change…**) under **Unlock PIN** in a device's **Info** tab
stores the device's PIN or password in the desktop keyring with
`secret-tool` (libsecret: gnome-keyring, KWallet, …), never in OmaDroid's
settings, logs or command arguments. It is keyed by the device's hardware serial
(`ro.serialno`) as reported live, never by its adb address, and bound to the
device's identity: saving also stores a sha256 of `ro.serialno` and
`android_id`. The serial alone isn't enough, since Wireless debugging
advertises it over mDNS (`adb-<serial>-…`); `android_id` isn't advertised,
and only its hash is kept on this computer. Unlocking:

1. wakes the device, then reads both values again and refuses, before
   anything is typed and without spending the one attempt, if the identity
   differs from the one the PIN was saved for (after a factory reset, save the
   PIN again);
2. does nothing more if no lock screen is showing;
3. opens the bouncer (`wm dismiss-keyguard`) and types only once a PIN or
   password field is on screen (`uiautomator`), so a pattern lock or a missing
   bouncer costs no attempt;
4. types the secret through `adb shell` stdin and presses Enter, **once**. If the
   lock screen is still showing, unlocking is paused for that device until the
   secret is saved again, so a wrong or outdated PIN never runs into Android's
   lockout or wipe limits.

When a saved PIN can't be used (unlocking is paused, or it was saved without the
device's identity), the device page says so under its controls with a **Save
PIN…** button that opens the PIN field right there, and the control reads
**Wake** instead of **Unlock** until it is saved again.

Passwords may use printable ASCII (4–64 characters, inner spaces allowed);
`input text` can't type accents or emoji, so those are refused when saving.
Pattern locks aren't supported. While it is typed, the secret briefly
appears in the arguments of the device's own `input` command, visible to
processes on the device itself.

The identity check keeps the PIN from a different device that turns up on a
reused address or advertises a copied serial. It is not a defence against
someone who already has adb access to your device: they can read the same
`android_id`, and they already control the device fully without the PIN.

Settings (⚙) chooses when this happens: **Wake** under **When mirroring
starts** (on by default), **Unlock** under **When mirroring starts**, and
**Wake** and **Unlock** under **When a device connects** (off). A device without a saved PIN is only woken. Devices already
connected when the shell starts are not woken or unlocked; only their keepers
return. A failed wake or unlock is reported and never blocks the mirror launch.
Preferences live under `$XDG_STATE_HOME/omadroid/devices` (marker files and
the identity hash, no secrets); keepers are tracked under `$XDG_RUNTIME_DIR/omadroid-$UID/keepers`.
