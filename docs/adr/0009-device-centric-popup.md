# 9. Device-centric popup instead of six flat tabs

- Status: Accepted
- Date: 2026-10-18 (`e7e704f`; session cards `c1490d3`)

## Context

Through 0.9.0 the popup had six flat tabs: Devices, Wireless, Mirror, Webcam,
Sound and Settings. Global pages (Wireless, Settings) sat next to per-device
ones, and each per-device page had its own device picker, so every new
feature meant another tab and another picker. Device cards showed serials,
mDNS service lines, hint paragraphs and two rows of buttons whether a device
was ready, offline, unauthorized or only nearby. The mirror page
(`ScrcpyPane.qml`) had grown to 1334 lines.

## Decision

- `Panel.qml` becomes a small router over four views: `home` (the device
  list), `device` (one device's page), `add` (Add device: QR code, pairing
  code, address) and `settings` (behind ⚙ in the header).
- Home groups rows into CONNECTED, NEEDS ATTENTION and NEARBY
  (`DeviceListModel.js`) with one inline action per row (Reconnect, Connect,
  Pair); serials and endpoints move to the tooltip and the Info tab.
- A device page has a hero, three session cards (Mirror, Audio, Webcam) with
  their options behind ⚙, one compact row of device controls, and Sound · Info
  sections. Nothing on the page picks a device: it is the page's device.
- `DeviceActions.js` keeps two registries, session kinds and device controls;
  a new feature is one entry plus one handler.
- One `MirrorSession` per panel feeds the bar icon, a session banner shown on
  every view (click opens the session's device, ■ stops it) and every device
  page.
- Esc steps back before closing; a page whose device disappears returns home
  with a notice instead of showing another device.

## Consequences

- New per-device features slot into a registry instead of a new tab.
- The 1334-line pane was split into `MirrorSession`, `SessionCard`,
  `MirrorOptions`, `WebcamOptions` and the device-page components.
- Reaching a session's controls takes one click on the banner from any view.
- Smoke checks and preview pages were rewritten for the new routes
  (`tests/smoke/SmokeSessions.qml`, `OMADROID_PREVIEW_PAGES`).
