# 12. Keep modules small: split by responsibility, files under 500 lines

- Status: Accepted
- Date: 2026-10-18 (`870932e`, `7297c66`); the 500-line budget comes from the
  coding guidelines added on 2026-09-08 (`ca4ede7`)

## Context

The project's coding guidelines ask for files under 500 lines, one
responsibility per module and short functions. Two files had outgrown that:
`ScrcpyPane.qml` (1334 lines) and `Model.js` (666 lines), which mixed
endpoint and adb/mDNS parsing, device rows, profiles and scrcpy commands with
webcam projections and device-info parsing. The Node tests also copy-pasted
the `vm` loading of each module.

## Decision

- Split by responsibility rather than by size alone. `Model.js` keeps
  endpoints, adb/mDNS parsing, device rows, status text, profiles and scrcpy
  commands; `Webcam.js` takes the camera list, options, presets, the scrcpy
  camera command and setup steps; `DeviceInfo.js` takes device-info parsing,
  sizes, labels and Info rows. Other projections have their own modules
  (`DeviceListModel.js`, `DeviceActions.js`, `DevicePage.js`,
  `SoundVolume.js`, `SendText.js`, …).
- Modules depend on each other with QML's `.import "X.js" as X`
  (`Webcam.js` imports `DeviceInfo.js`).
- `tests/load-js.cjs` loads a module the way QML does, resolving its `.import`
  lines into namespaces, and tests follow their modules
  (`webcam.test.cjs`, `device-info.test.cjs`).

## Consequences

- Every QML, JS, shell and Python file in the plugin is under 500 lines; the
  largest are around 370.
- Pure logic stays in `.js` modules that Node tests run without a shell.
- Some features span several small files, so the
  [architecture overview](../architecture.md) lists which file owns what.
