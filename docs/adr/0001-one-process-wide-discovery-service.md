# 1. One process-wide discovery service shared by all widgets

- Status: Accepted
- Date: 2026-09-12 (`a8e6ad4`; mDNS hold added 2026-09-28, `4e904e3`)

## Context

Omarchy creates one bar widget per bar, so a two-monitor desktop had two
`Panel.qml` instances. Each one ran its own `adb devices` scans and Avahi
browsers: twice the processes, overlapping scans, and two widgets that could
disagree about the same phone. Anything that acts on a device event (later:
auto-connect, wake or unlock on connect) would also act once per monitor.

## Decision

Device discovery is the plugin's `service` entry point (`Discovery.qml` in
`manifest.json`), which the shell creates once per process. Widgets and the
Send text overlay reach it through `DiscoveryConsumer.qml`, a thin adapter that
calls `shell.serviceFor("pym.omadroid")` and forwards `refresh()`,
`holdMdns()`, `setPreference()` and `setAutoConnect()`. Consumers own no
commands or timers.

- Refresh requests that arrive while a scan runs are coalesced
  (`refreshPending`), so scans never overlap.
- Avahi runs only while a consumer holds mDNS (an open popup) or Auto-connect
  is on; holders are tracked per consumer and released on destruction.
- Everything that reacts to devices (`Preferences`, `AutoConnect`,
  `PowerOnConnect`) is a child of the service, so it acts once.

## Consequences

- One `adb track-devices` and at most one set of Avahi browsers per shell,
  whatever the number of monitors; every widget shows the same rows.
- Settings changed in one popup show in every other one at once.
- A widget without a shell (a standalone test host) gets an empty stand-in
  from `DiscoveryConsumer` instead of failing to load.
- `tests/shared-discovery.sh` creates two consumers of one injected service
  and checks that one tracker serves both and refreshes never overlap.
