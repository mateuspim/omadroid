# 3. Push-based device discovery, with polling only as a fallback

- Status: Accepted
- Date: 2026-10-04 (`04c253f`)

## Context

Discovery scanned: `adb devices -l` on a timer and `avahi-browse --terminate`
on each refresh. Plugging in, authorizing or losing a device showed only on
the next scan, scans cost processes even when nothing changed, and each scan
rebuilt the list. The host's adb also reports that its mDNS support is not
built in, so adb's own `mdns services` could not replace Avahi.

## Decision

- Follow `adb track-devices -l` with one long-running `CommandStream`; its
  frames (4-hex length + payload) are decoded by `Model.takeTrackFrames`.
  Nothing polls while it runs.
- If the tracker stops (adb missing, server restarting), poll
  `adb devices -l` every `refreshIntervalSec` (default 15 s, 5–3600 s in
  Settings) and retry the tracker after 1, 2, 4 … up to 60 s.
- `discover-mdns.sh` keeps one `avahi-browse --resolve --parsable` per service
  type open until terminated; resolved records and removals stream to the
  plugin as Avahi sees them. Browsers run under `setpriv --pdeathsig TERM`, so
  a SIGKILLed helper leaves none behind. Any browser exit ends the helper,
  which is reported and restarted after 10 s.
- Records are sorted before parsing (the three browsers race), and
  `Model.sameData` keeps unchanged arrays, so bound views are not rebuilt.
- After the browsers (re)start, the previous rows stay for 1.5 s while they
  catch up, so reopening the popup doesn't flicker.

## Consequences

- Device changes show at once; an idle desktop runs one `adb track-devices`
  and no Avahi (unless Auto-connect is on).
- ↻ / F5 remain as an explicit re-read and browser restart.
- The fallback path needs its own test: `tests/shared-discovery.sh no_track`.
- Device details (`device-info.sh`) are still read, not pushed: Android has no
  event for them, so they are read while a popup is open and refreshed after
  60 s.
