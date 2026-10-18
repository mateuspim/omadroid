# 8. Offscreen preview and smoke harness instead of desktop windows

- Status: Accepted
- Date: 2026-10-18 (`076e322`)

## Context

Visual review used `tests/smoke.sh` in a preview mode that opened a floating
window on the developer's live desktop. It needed the real Wayland socket,
could time out before every frame was captured, never ran discovery (there
was no bar shell), and a preview that launched a fake session could leave mock
scrcpy loops running. A UI redesign was about to need renders of every view.

## Decision

- Previews run offscreen like the smoke test (`QT_QPA_PLATFORM=offscreen`,
  `WAYLAND_DISPLAY` and `DISPLAY` unset) and write one PNG per view to
  `OMADROID_PREVIEW_DIR`. No window opens.
- The shell's `KeyboardPanel` needs a `PanelWindow`, which has no offscreen
  backend, so previews link `tests/offscreen-ui/KeyboardPanel.qml`, a plain
  `Item` stand-in, over the installed `Ui` module.
- The panel gets a fake bar whose shell's `serviceFor` returns a real
  `Discovery` running against the mock adb and Avahi in `PATH`, so previews
  show real discovery output.
- `OMADROID_PREVIEW_PAGES` picks the views and steps (`home`, `device-sound`,
  `click-webcam`, …) and `OMADROID_PREVIEW_QML` swaps the capture script
  (`tests/HomePreview.qml`, `tests/DevicePreview.qml`).

## Consequences

- Previews and smoke tests can run during a desktop session without
  disturbing it, and every view can be reviewed after each change.
- Everything runs in a temporary directory with isolated XDG dirs and mocks,
  removed on exit.
- Previews need the QtTest QML module. Effects that need a real scene graph
  may render differently offscreen, and offscreen renders don't replace a
  live check in the shell.
