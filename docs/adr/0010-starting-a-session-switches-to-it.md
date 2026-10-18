# 10. Starting a session while another runs switches to it

- Status: Accepted
- Date: 2026-10-18 (`f05f846`, `cf7b319`; card confirm `c1490d3`)

## Context

Only one scrcpy session runs per machine
([ADR 2](0002-one-scrcpy-session-per-machine.md)). A launch while another
session ran used to be ignored until the user stopped the first one by hand,
so checking the webcam while mirroring took several steps. Stopping a session
also finalizes its recording, which should not happen by accident. And a first
version of switching, applied to a session that was still starting, stopped
nothing real and then looped stop/launch until the first launch landed and was
killed.

## Decision

- `MirrorSession.launchMirror` / `launchWebcam` call `switchTo(kind, serial,
  launch)` while a session is busy. It stores a `pendingSwitch`, stops the
  running session and runs the launch once the status shows it ended.
- Only a running session is switched: the PID must be known and no wake/unlock
  preparation running. Otherwise the click reports "Wait until the current
  session has started." A second switch while one waits is ignored.
- The user's Stop (■ on the banner, Stop in the controls) cancels a pending
  switch at any point; a failed stop drops it. `switchTo` stops through an
  internal `stopRunning()` so it doesn't cancel itself.
- If the running session records, the card first shows "Stop recording &
  switch?" and needs a second click within 4 s (`DeviceSessions.qml`).
- Webcam **Apply** is a switch to the same phone and output with the new
  settings (`OMADROID_KEEP_READERS=1`, so apps reading the output don't block
  it). A webcam started from the panel opens its preview (`previewWanted`).
- Cards read "Switch · stops …" and the banner "Switching to …" while a switch
  is pending.

## Consequences

- Mirror ↔ audio ↔ webcam, or another phone, is one click (two when
  recording).
- The separate webcam restart state (`restartPending` / `restartTarget`) gave
  way to `pendingSwitch`; `restartPending` remains as a derived flag.
- `tests/mirror-session.test.cjs` covers mirror → webcam, switching phones,
  Stop cancelling a waiting switch, a second launch being ignored and the
  starting guard; the smoke test checks a mirror → webcam switch and the
  recording confirm.
