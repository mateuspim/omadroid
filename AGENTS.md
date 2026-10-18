# OmaDroid agent instructions

OmaDroid is an Omarchy shell plugin (Quickshell/QML + bash) that discovers
Android devices over adb and mirrors/controls them with scrcpy. Plugin id
`pym.omadroid`; public at https://github.com/mateuspim/omadroid. The README
is the user manual; read its section before changing a feature.

## Project

- Layout:
  - Root: every `.qml` and `.js` file. Omarchy loads the entry points named
    in `manifest.json` (`Panel.qml`, `SendText.qml`, `Discovery.qml`), and
    QML resolves sibling components through implicit same-directory imports,
    so the UI stays flat. Don't add QML subfolders.
  - `scripts/`: the bash helpers (and `audio-codes.py`) the UI runs. QML
    finds them with `Qt.resolvedUrl("scripts/x.sh")`; scripts find each other
    through their own directory (`$(dirname -- "${BASH_SOURCE[0]}")`).
  - `tests/`: Node unit tests (`*.test.cjs`), shell suites, `mock-*.sh` fake
    executables and the headless QML harnesses (`Smoke.qml`, `Preview.qml`).
- Naming: env vars `OMADROID_*`, objectNames `omadroid…`, plugin id
  `pym.omadroid`, settings `~/.config/omarchy/omadroid.ini`, keyring
  attribute `app omadroid`, terminal app-id `io.github.mateuspim.omadroid`.
  Never reintroduce `DroidLink`/`droidlink` or new `org.omarchy.*` ids (the
  webcam setup reusing `org.omarchy.terminal` is the one exception, ADR 13).
- Qt 6.12: QtQuick exports its own `Color`. Write
  `import qs.Commons as Commons` and `Commons.Color.x`; never a bare `Color.`.
- Shell scripts: bash, `set -uo pipefail` (or `-euo`), plain-text results on
  stdout for QML to parse, errors on stderr with a non-zero exit. Keep the
  user-facing scripts executable.
  When running `scripts/session.sh` by hand, use an absolute path: it re-execs
  `bash "$0" run` inside a new terminal.

## Code style

- Functions: 4-20 lines. Split if longer.
- Files: under 500 lines. Split by responsibility.
- One thing per function, one responsibility per module (SRP).
- Names: specific and unique. Avoid `data`, `handler`, `Manager`.
  Prefer names that return <5 grep hits in the codebase.
- Types: explicit. Typed QML properties (`property string`, `property int`)
  over `property var` where the shape is known; `local` for shell variables.
- No code duplication. Extract shared logic into a function/module (pure JS
  in a `.js` file so Node can test it; shared bash in `scripts/*-lib.sh`).
- Early returns over nested ifs. Max 2 levels of indentation.
- Exception messages must include the offending value and expected shape.

## Comments

- Keep your own comments. Don't strip them on refactor — they carry
  intent and provenance.
- Write WHY, not WHAT. Skip `// increment counter` above `i++`.
- Docstrings on public functions: intent + one usage example.
- Reference issue numbers / commit SHAs when a line exists because
  of a specific bug or upstream constraint.

## Tests

- Everything runs with one command: `bash tests/run-all.sh` (prints
  `OMADROID_ALL_OK`; stops at the first failure, naming it). Node unit tests
  alone: `node --test tests/*.test.cjs`. A new shell suite must be added to
  the list in `tests/run-all.sh` or the run fails.
- Every new function gets a test. Bug fixes get a regression test.
- Mock external I/O (adb, scrcpy, avahi, keyring, terminal, filesystem) with
  named fakes (`tests/mock-*.sh`, fixture dirs), not inline stubs. Tests never
  touch a real device, the real keyring or the user's config.
- Tests must be F.I.R.S.T: fast, independent, repeatable,
  self-validating, timely.
- Visual check, offscreen (never pops a window):
  `OMADROID_PREVIEW_DIR=<abs dir> bash tests/smoke.sh` writes one PNG per
  view. `OMADROID_PREVIEW_PAGES=home,device,…` picks views (list in
  `tests/Preview.qml`); `OMADROID_PREVIEW_QML=tests/DevicePreview.qml` (or
  `HomePreview.qml`) swaps the capture script. Offscreen renders skip
  MultiEffect. Afterwards `pgrep -af omadroid-smoke` and kill your leftovers.
- Live shell log (read-only):
  `quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i omadroid`.
  Don't restart the user's shell (`omarchy-restart-shell`) or run live
  device/desktop tests without asking.

## Dependencies

- Inject dependencies through constructor/parameter, not global/import
  (e.g. script paths and command runners passed into JS builders).
- Wrap third-party tools behind a thin interface owned by this project
  (adb/scrcpy calls go through `scripts/`, parsed by `.js` projections).

## Structure

- Follow the framework's convention: Omarchy plugin manifest + QML entry
  points at the root, as above.
- Prefer small focused modules over god files.
- Predictable paths: UI in `*.qml`, testable logic in `*.js`, system work in
  `scripts/`, tests in `tests/`.

## Formatting

- Use the language default formatter (`qmlformat` for QML, `prettier` style
  for JS, 2-space bash). Match the surrounding file; don't discuss style
  beyond that.

## Logging

- Structured JSON when logging for debugging / observability
  (`console.warn(JSON.stringify({ omadroid: "…", error: … }))`).
- Plain text only for user-facing CLI output and script results.

## Public-repo hygiene

- No `/home/...` paths, real device serials or names, or LAN addresses in
  tracked files (tests use `USB123`, `adb-PHONE-random` and similar).
- Secrets (unlock PINs, pairing passwords) never go in argv, logs or
  settings: pipe them through stdin. Never run `secret-tool search`; it
  prints secrets.
- Files outside the plugin (e.g. Hyprland binds) change only through an
  explicit in-plugin Install/Remove button that touches its own marked block
  (see `scripts/hotkey.sh`). Never modify user config on load.
- `HANDOFF.md` is local-only and stays gitignored.

## Releases

1. Bump `version` in `manifest.json` and add a `CHANGELOG.md` entry.
2. `bash tests/run-all.sh` → `OMADROID_ALL_OK`.
3. `omarchy plugin validate .` exits 0.
4. Commit, then tag `vX.Y.Z`. Ask the owner before pushing commits or tags.
