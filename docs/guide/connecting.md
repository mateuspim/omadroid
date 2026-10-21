# Connecting a device

Connect over USB or wireless debugging, pair with a QR code, move a USB device to Wi-Fi, and reconnect trusted devices automatically.

For USB, enable USB debugging, connect a data cable, unlock Android, and accept
the authorization prompt. The popup shows unauthorized, offline, permission,
recovery, and other ADB states; only `device` state enables mirroring. USB is
disconnected by unplugging the cable: `adb disconnect` only disconnects network
transports.

For Android wireless debugging, keep the phone and computer on the same network:

1. Enable Developer options → Wireless debugging on Android.
2. Choose **Connect** on the discovered device under **NEARBY**. If this
   workstation is already paired, it connects immediately.
3. If the connection fails, OmaDroid opens **Add device** › **Pairing code**
   with the discovered host/IP locked in place. Open **Pair device with pairing code** on Android, then
   enter only its separate pairing port and six-digit code. If Android's
   pairing service is already advertised, its actual pairing port is filled in.
4. Select **Pair**. OmaDroid then connects to the connection port Android
   advertises for the same host. If that service isn't known yet, it waits for
   one discovery refresh before asking you to connect manually. **Pair** on
   an advertised pairing service and the fully manual **Pairing code** and
   **Address** forms remain available in **Add device**.

Pairing codes are passed on stdin, cleared after submission or dismissal, and
never saved in profiles or included in command arguments. Pairing grants ADB
trust; disconnecting does not forget that trust. Forget the host on Android to
revoke it. The plugin issues connection commands only on explicit clicks;
ADB itself may automatically connect to previously trusted mDNS services.

Discovery recognizes `_adb._tcp`, `_adb-tls-connect._tcp`, and
`_adb-tls-pairing._tcp`. Android runs one wireless ADB endpoint per host, so a
connection service on the host of a wireless device is merged into that device even
when the ports differ: a ready device keeps the port ADB is using (Avahi can briefly
hold a stale one), and an offline device takes the newly advertised port, so its
**Reconnect** button reconnects after Wireless debugging is toggled. Offline entries ADB
keeps for a host that is ready again on another port are hidden. USB and Wi-Fi
remain separate transports, and pairing ports remain distinct. mDNS does not supply a reliable hardware serial or model name,
so unconnected entries explicitly show a service identity instead.

The plugin invokes `bash scripts/discover-mdns.sh` using its resolved plugin path. The
script keeps one `avahi-browse` open per Android service type while the popup is
open, and stops them when it closes. Resolved records and removals stream to the
plugin as Avahi sees them, so devices appear and leave without a rescan; the
plugin decodes names, shows one row per service (IPv4 preferred), and adds interface scopes to
link-local IPv6 addresses. Pairing and connection ports remain distinct. On
opening, the previous results stay shown for 1.5 seconds while the browsers
catch up, so the list doesn't flicker. If any browser stops, the error is shown
and the browsers are restarted after 10 seconds.

This path does not invoke `adb mdns services` and works independently of ADB's
mDNS build support. If Avahi is missing or its daemon is unavailable, the popup
reports the error and keeps USB and manual wireless controls available. The
script does not start or configure the daemon. Some networks block multicast.
No automatic ADB server restart, package installation, or broad disconnect is
performed. Wireless debugging and TCP mode are only switched on by an explicit
click on **Wireless** ([Go wireless](#go-wireless)).

## Pair with a QR code

On Android 11 or later, open **+ Add device**, choose **QR code** and
**Show QR code**, then on Android
open Developer options › Wireless debugging › **Pair device with QR code** and
scan it. Nothing needs to be typed or installed on the phone.

`scripts/qr-pair.sh` makes a one-time service name (`omadroid-` and 8 random
characters) and a 16-character password from `/dev/urandom`, and encodes
`WIFI:T:ADB;S:<name>;P:<password>;;`, the payload Android Studio uses. The
payload reaches `qrencode` on stdin, never in a process's arguments. Once
scanned, Android announces `_adb-tls-pairing._tcp` under that name; OmaDroid
waits for that exact service, so another device's pairing service is never
used, then runs `adb pair` with the password on stdin and connects as after
code pairing. The code is held in memory only while it is shown, and is
dropped when you cancel, leave Add device, or close the popup (wireless
discovery stops with the popup, so it could no longer pair). Showing a code
needs wireless discovery; the button is disabled while Avahi is unavailable.

## Go wireless

A ready USB device's control row has **Wireless**. With the cable still in,
clicking it runs `scripts/go-wireless.sh`, which:

1. Reads the device's Wi-Fi IPv4 address (`wlan*`; mobile data doesn't count).
2. On Android 11+, turns on Wireless debugging (`settings put global
   adb_wifi_enabled 1`), waits for the port adbd publishes in
   `service.adb.tls.port`, and connects to it. A host already trusted over USB
   is usually accepted without pairing. If it isn't, OmaDroid says so and
   points to pairing with a QR code in **Add device**. If Android asks whether to allow wireless
   debugging on this network, allow it.
3. On Android 10 and older, runs `adb tcpip 5555` and connects to port 5555.
   That mode is unencrypted and ends when the device reboots.

It then waits for the wireless transport to be ready and tells you to unplug
the cable. Wireless debugging stays on afterwards; turn it off on Android when
you're done.

## Auto-connect

Turn on **Auto-connect** under **Wireless** in the popup's Settings (⚙). It is
saved in OmaDroid's own `omadroid.ini` (`[autoConnect] enabled`). Then, when a device that was connected here before turns on
Wireless debugging (the Quick Settings developer tile is quickest), OmaDroid
connects it without a click, even with the popup closed.

- A device is remembered once it is ready over Wi-Fi here, however it got
  connected (QR pairing, Go wireless, Connect), by its Wireless debugging
  service name minus the random suffix (`adb-<serial>`). Up to 50 are kept in
  `omadroid.ini` under `[autoConnect]`, and remembering happens whether or
  not the setting is on.
- Each announced endpoint gets one `adb connect`. A device that refuses this
  computer (unpaired on Android) is forgotten until it connects again; a
  network failure waits for the next announcement. Toggling Wireless debugging
  announces a new port, which is tried once.
- Devices that were never connected here are never contacted.
- The Avahi browsers keep running while the setting is on, even with the popup
  closed. Device details are still only read while the popup is open.
