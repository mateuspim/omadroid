# Mirroring and profiles

Mirror and Audio sessions: profiles, the phone screen and rotation, staying awake, recording, and how sessions run.

⚙ on the **Mirror** or **Audio** card opens the **Mirror & Audio profile**
they share; the cards' summaries follow it.

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
`$XDG_CONFIG_HOME/omarchy/omadroid.ini` (normally
`~/.config/omarchy/omadroid.ini`). Unsaved changes last until the widget reloads.
**Reset** restores edited options from the profile selected before those edits. It
does not modify Omarchy settings, saved profiles, the recording folder, or any
device connection.

## Phone screen and orientation

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
to release the lock and restore sensor-based rotation. `scripts/session.sh rotate` runs
these commands against the active session's device and does not restart scrcpy.

When the controls appear, including after an Omarchy shell restart, they read
`settings get system accelerometer_rotation` and `user_rotation` to show the
phone's current lock. OmaDroid records a lock it set under
`$XDG_RUNTIME_DIR/omadroid-$UID/rotation` and sends `wm user-rotation free`
when that session ends, whether it was stopped, its window was closed, or
scrcpy exited. **Auto rotate / reset** clears that record. A lock chosen on the
phone is reported as such and left in place.

Android or an app can exclude protected content from capture. Authenticate on
the physical phone in that case; OmaDroid does not detect protected prompts
automatically or change Android's capture protections.

**Stay awake** uses scrcpy 4.1's `--keep-active`, which also works without
a charger. Selecting **Screen off** enables it; it can be unchecked
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
when forwarding is enabled and supported. Use **Stop** in the session controls
(its tooltip says **Stop mirroring**), the "● Running" card, ■ on the session
banner, or close the scrcpy window to finalize a recording. Switching to
another session finalizes it too, after the confirm described under
[Features](features.md).
Scrcpy runs in foot when it is installed, otherwise in Omarchy's configured
default terminal, on a hidden `special:omadroid` workspace, leaving only the
scrcpy video window visible. Foot is preferred because each of its windows is a
separate process, so OmaDroid never shares a process with your own terminals.
Press **Log** in the session controls, or beside the last session message on
the device page once it has ended (or run
`hyprctl dispatch 'hl.dsp.workspace.toggle_special("omadroid")'`) to show or hide its
diagnostic terminal. The terminal is asked to stay open after scrcpy exits if
the configured terminal supports that option; the next launch closes the
previous session's terminal. Closing the popup, switching
views or devices, or restarting the Omarchy shell leaves the session running. Every monitor's
widget reads the same session state and can stop it; only one OmaDroid session
runs at a time, and starting another switches to it. Nothing polls the session: widgets watch its state file, and
while a session runs `scripts/session.sh wait` sleeps on the scrcpy process (util-linux
`waitpid`) and ends the session, releasing a rotation lock OmaDroid set, as soon
as scrcpy exits, even with the popup closed. Closing the terminal also ends the session. A device that
disappears while its page is open returns the popup to the device list with a
notice; it is never silently replaced by another phone.

All external programs use argument arrays, not shell interpolation. Session state
lives under `$XDG_RUNTIME_DIR/omadroid-$UID` and is checked against the process
start time so a stale PID is ignored. Stop sends `TERM` to scrcpy so it can close
streams and finalize recordings, then force-kills only a session that fails to exit.
Discovery and ADB actions have bounded timeouts; their diagnostics are bounded and
shown in the popup. A wireless device that is still advertised but doesn't answer
(asleep, or Wireless debugging off) gets one muted hint; hard failures such as a
stopped `avahi-daemon` are shown as errors. Hover the message for Avahi's full
output. Scrcpy diagnostics remain in the hidden terminal while it is
open. ADB's failure messages are checked even when it exits with code 0.
