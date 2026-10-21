# Android webcam setup

Use a phone's camera as a V4L2 webcam: setting up the loopback output, the camera options and the in-panel preview.

Camera capture requires Android 12 or later, scrcpy 4.1+, and a Linux
`v4l2loopback` output. Until one is usable, the **Webcam** card reads "Needs
setup", and its options (⚙) say whether the package is missing, the kernel
module is unavailable or unloaded, or no output is visible. **Set up
webcam** or **Enable output** opens a visible terminal after you click it;
Omarchy's package helper and `sudo` ask for a password there. It loads one
output now and at every boot, by writing
`/etc/modules-load.d/v4l2loopback.conf` and `/etc/modprobe.d/v4l2loopback.conf`;
if either file already exists, your config is kept and only `modprobe` runs.
**Copy commands** puts the manual commands on the clipboard. On Omarchy, those
commands, which are also what the setup terminal runs, are:

```bash
omarchy pkg add v4l2loopback-dkms
sudo modprobe v4l2loopback devices=1 exclusive_caps=1
printf 'v4l2loopback\n' | sudo tee /etc/modules-load.d/v4l2loopback.conf
printf 'options v4l2loopback devices=1 exclusive_caps=1\n' | sudo tee /etc/modprobe.d/v4l2loopback.conf
```

The output then takes the next free `/dev/videoN` and the driver's default
label. To pick both, load it yourself instead, using an unused number:

```bash
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="OmaDroid Camera" exclusive_caps=1
```

A bare `modprobe` lasts until reboot; to choose your own options at boot, edit
the `options` line in `/etc/modprobe.d/v4l2loopback.conf`. See the
[v4l2loopback README](https://github.com/v4l2loopback/v4l2loopback/blob/main/README.md)
for other distributions and module options.

`exclusive_caps=1` makes the device appear as a capture device to applications
after scrcpy starts writing. If you already have loopback devices, use their
existing numbers and labels; OmaDroid lists detected loopback outputs so you
can choose the right one and checks write access before launch. Opening the
popup or the webcam options never installs or loads anything. Other USB cameras
are never listed as outputs.

Open a ready phone, pick the camera and V4L2 **Output** under the **Webcam**
card's ⚙ if the defaults don't suit, then click the card.

Opening the webcam options asks the phone for its cameras (`scrcpy --list-camera-sizes`)
once per device; **Refresh** asks again and also finds V4L2 outputs. Every camera is listed by its id,
so a phone with two front cameras offers both, and Resolution, Frame rate and
Zoom only offer what the chosen camera reports. Until the list arrives, Front
and Back and common sizes are offered.

- **Quality**: a preset (**Call** 1080p · 30 fps · 12 Mbps H.265, **Sharp** 4K
  · 30 fps · 24 Mbps H.265, **Saver** 720p · 24 fps · 6 Mbps H.264) picks the
  closest size and rate the camera supports. Resolution, Frame rate, Bitrate
  and Codec can also be set by hand under **Adjust**, which shows the preset as Custom. Over
  Wi-Fi, bitrate is usually what limits sharpness; H.265 looks better than
  H.264 at the same bitrate. Automatic resolution leaves the size to scrcpy,
  which may pick the full sensor size.
- **Adjust** (folded under the Quality summary): Resolution, Frame rate,
  Bitrate, Codec, Orientation (rotate or mirror), initial Zoom, Torch (on
  cameras with a light), and Smoothing, a `--v4l2-buffer` delay that hides
  Wi-Fi jitter.

Settings are saved in `omadroid.ini` and apply when the webcam starts;
Android cameras top out at the frame rates the phone lists (often 30 fps).
Exposure, focus and white balance stay automatic: scrcpy has no controls for
them. While a webcam runs, changing a setting shows **Apply · restart**, which
stops and restarts the webcam on the same phone and output with the new
settings. Apps reading the output may stay open through the short gap when
the size and orientation stay the same; if they change, close those apps
first, or scrcpy reports the output as busy. If a size fails, select Automatic or another size and use **Log**
for the phone's error. The Android webcam sends video only; it
does not forward the phone microphone. Start the webcam before opening OBS or a
video call, then select the chosen `/dev/videoN` or its card label as a **Video
Capture Device** in OBS or as the camera in the call. A consumer that stays
open across a size or orientation change can keep the old V4L2 format and show
garbled video; the preview detects that and says so. **Stop** on the session
controls, a click on the "● Running" card, or ■ on the session banner ends the
shared scrcpy session from any OmaDroid bar instance.

While the webcam runs, its preview shows the output inside the popup, read the
same way OBS or a call reads it, so a working preview means other apps receive
the camera. A webcam started from the popup opens its preview by itself once
scrcpy is streaming, if the popup is still open; **Preview** / **Hide** in the
session controls toggles it. An Omarchy loading screen covers it until frames
arrive. It follows the session's own output, and closes when the popup closes
or you leave the device's page. It
runs `ffmpeg`, which reads the output at its current size and writes a small
JPEG (480 px wide, about 12 per second) to OmaDroid's runtime folder; ffmpeg
also exits if the shell does. If apps reading the output receive a different
size than scrcpy writes (an app that opened it during an earlier session can
fix its old size), the preview says so instead of showing garbled video: close
every app using the output, then stop and start the webcam.
