# Features

What the popup shows and what each part of it does.

The popup opens on a device list grouped into **CONNECTED**, **NEEDS
ATTENTION** and **NEARBY**. Click a ready device to open its page:

1. a hero with its name, model, Android version, connection, battery, storage
   and memory;
2. three **session cards**, **Mirror**, **Audio** and **Webcam**, each with a
   live summary of what a click starts (for example "Balanced · 1080p · 8
   Mbps", "Opus · no video", "Front · 1080p · 30 fps");
3. one compact row of device controls: **Wake** (**Unlock** once a PIN is
   saved), **Lock**, **Awake**, **Text**, and **Wireless** for a USB device or
   **Disconnect** for a Wi-Fi one;
4. the **Sound** and **Info** tabs.

**+ Add device** at the bottom of the list pairs or connects a wireless
device, and ⚙ in the header opens **Settings**. A running mirror, audio or
webcam session shows as a banner on every view; click it to open that
device's page, or ■ to stop it.

- **Devices:** one process-wide discovery service follows `adb track-devices -l`
  for every monitor, so plugging in, authorizing or losing a device shows at
  once without polling, plus Avahi-based mDNS discovery that follows the network
  while the popup is open. Each row shows the device name with its model and
  battery, or what it needs (accept the USB debugging prompt, offline, …); the
  serial or service identity and address are in its tooltip. A row that needs
  you has one inline action: **Reconnect** for a wireless device that went
  offline, **Connect** for a discovered one, **Pair** for an advertised pairing
  service. The name is the one set on Android (Settings › About › Device name),
  read once per connection; devices without one show their model. The **Info**
  tab adds temperature, SD card or USB drive storage, and screen size with its
  aspect ratio, plus the serial and address with copy buttons. Sizes use
  1000-based units (GB, TB), as Android's Settings does. Details are read with
  one `adb shell` per device while the popup is open and refreshed once they
  are a minute old; nothing is read while it is closed. The bar badge counts
  authorized, ready transports. ↻ in the header (or F5) re-reads ADB and
  restarts the Avahi browsers; its tooltip says how fresh the list is. If the
  ADB tracker stops (adb missing, its server restarting), OmaDroid polls
  `adb devices -l` every 15 seconds by default (**Scan interval** in Settings
  accepts 5–3600 seconds) and retries the tracker with a growing delay of up
  to a minute.
- **Wireless:** **Add device** pairs by scanning a QR code with Android
  (**QR code**), by six-digit code (**Pairing code**, prefilled from
  discovered services) or connects to a paired device by manual `IP:port` /
  `hostname:port` / `[IPv6]:port` entry (**Address**). A USB device's
  **Wireless** control moves it to Wi-Fi so the cable can be unplugged, and a
  wireless device's **Disconnect** drops the connection. See
  [Pair with a QR code](connecting.md#pair-with-a-qr-code) and [Go wireless](connecting.md#go-wireless).
- **Session cards:** a click starts that session with the options shown in its
  summary. ⚙ on a card opens its options under the cards, one panel at a
  time: **Mirror** and **Audio** share the **Mirror & Audio profile**
  (resolution, FPS, H.264/H.265/AV1 codec, video bitrate, and the **Audio**,
  **Record**, **Screen off**, **Stay awake** and **Fullscreen** options);
  **Webcam** has its camera settings. **Audio** plays the device's sound
  without a scrcpy window (`--no-video --no-window`); its optional recordings
  are saved as `.mka`. While a session runs on the device, its controls
  (Preview, Log, Stop, battery, recording, phone screen and rotation) show
  under the cards. See [Mirroring and profiles](mirroring.md) and
  [Android webcam setup](webcam.md).
- **One-click switching:** only one session runs at a time. Starting any
  session while another runs, of another kind or on another phone, stops it
  and starts the new one: the cards read "Switch · stops …" and the banner
  "Switching to …" until it starts, and ■ cancels the switch. A mirror that
  records asks first ("Stop recording & switch?"): click again within about 4
  seconds to finalize the recording and switch. A session that is still
  starting can't be switched; the other cards wait until it runs. The running
  session's card reads "● Running", and clicking it stops the session.
- **Rotation:** the four orientation buttons during a video session lock the
  device to portrait, landscape, or either inverted orientation. **Auto
  rotate / reset** restores Android's sensor rotation. A lock set from
  OmaDroid is released when the session ends; a lock set on the phone is kept.
- **Keep awake, wake, unlock and lock:** **Awake**, **Wake** (**Unlock** once
  a PIN is saved) and **Lock** in the control row; the PIN is saved under
  **Unlock PIN** in the **Info** tab. See [Keep awake and unlock](keep-awake-and-unlock.md).
- **Sound:** the **Sound** tab has the device's volume keys, mute all, ringer
  mode, per-app volume and mute for the apps playing sound, and the system
  sound streams. See [Sound](sound.md).
- **Send text:** a hotkey, or the **Text** control, opens a centered prompt;
  what you type there is typed on the device. See [Send text](send-text.md).

The popup follows the active Omarchy theme and uses its native buttons, inputs,
dropdowns, typography, and keyboard focus styles. Tab moves between controls;
Enter/Space activates buttons and opens a focused device row; F5 refreshes;
Escape closes an open dropdown, then goes back to the device list, then
dismisses the popup. Every view scrolls when it doesn't fit.
