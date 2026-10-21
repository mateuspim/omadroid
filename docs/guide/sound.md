# Sound

The Sound tab: the device's volume keys, mute all, ringer mode, per-app volume and system streams.

A ready device's **Sound** tab controls that device:

- **− / +** press the device's own volume keys, so they change whatever
  Android would change (usually media) and show its volume panel.
- **Mute all** silences every sound on the device (Android's master mute);
  app and stream volumes are kept for when it is turned off.
- **Sound / Vibrate / Silent** set the ringer mode.
- **Apps** lists the apps that are playing sound, and paused ones that have a
  name or a changed volume. On Samsung phones and tablets each has a 0–100%
  volume slider and a mute toggle, the same setting as One UI's per-app volume
  (Sound Assistant). Other phones can only mute an app (`appops set UID
  PLAY_AUDIO ignore`).
- **System sounds** has a slider and mute toggle each for media,
  notifications, ringtone, calls, system, alarms and the assistant stream
  (Bixby on Samsung). Ringtone, notifications and system follow the ringer mode, so they
  read as muted on Vibrate and Silent.

Right-click a slider to mute it; the wheel scrolls the page. The tab reads the device
every 2 seconds while it is shown (Android has no volume change events for
the shell), and nothing while it is hidden or the popup is closed. While you
drag, only the latest value is sent.

Streams and the ringer use Android's `cmd audio`. Per-app volume and master
mute have no shell command: they are binder calls (`service call audio CODE`)
whose codes change with every firmware. The first time a firmware is seen,
`scripts/device-volume.sh` copies the device's `/system/framework/framework.jar`
(about 50 MB) and `scripts/audio-codes.py` reads the codes from it, which takes a few
seconds. They are cached in `~/.cache/omadroid/audio-codes/`. The parser
refuses a table it can't fully check, and before any code is used the device
is asked for the media volume both through that code and through
`cmd audio`; if they differ, per-app volume and **Mute all** are hidden and
nothing is called. App names come from `scrcpy --list-apps` and are cached per
device in `~/.cache/omadroid/apps/`, readable only by you.

Without the UI: `scripts/device-volume.sh status SERIAL`, `stream SERIAL media
set 10|raise|lower|mute|unmute`, `app SERIAL UID set 40|mute|unmute`, `master
SERIAL mute|unmute`, `ringer SERIAL normal|vibrate|silent`, `key SERIAL
up|down|mute`.
