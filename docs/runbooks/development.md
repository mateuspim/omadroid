# Development runbook

## Set up a checkout

OmaDroid is plain QML, JavaScript and bash: there is nothing to build and no
npm packages. You need the runtime [requirements](../../README.md#requirements-and-enabling)
plus, for the tests, Node (any current LTS), Python 3, ripgrep (`rg`) and
Omarchy's Quickshell shell (`/usr/share/omarchy/shell`) for the QML suites.

1. Clone the repository on branch `master`.
2. Link the checkout in place of the installed copy (move an installed copy
   aside first):

   ```bash
   ln -s /path/to/omadroid ~/.config/omarchy/plugins/pym.omadroid
   ```

3. Enable the widget if it is not in the bar yet:

   ```bash
   omarchy plugin enable pym.omadroid --section right
   ```

Omarchy watches the plugin directory and reloads changed QML. Read the live
shell log without restarting anything:

```bash
quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i omadroid
```

Don't restart the shell (`omarchy-restart-shell`) or run live device tests in
someone's session without asking them.

## Run the tests

```bash
omarchy plugin validate .
bash tests/run-all.sh
```

`tests/run-all.sh` runs the Node suites (`node --test tests/*.test.cjs`), then
each shell suite, including the `OMADROID_TEST_CASE` variants. It stops at the
first failure, naming it, and prints `OMADROID_ALL_OK` when everything passed.
A new shell suite must be added to its list, or the run fails. Run one suite
on its own with, for example, `bash tests/session.sh` or
`OMADROID_TEST_CASE=avahi_unavailable bash tests/smoke.sh`.

Every suite runs against named fakes (`tests/mock-*.sh`) in a temporary
directory with isolated XDG folders: no real device, keyring, Hyprland config
or user settings is touched. The QML suites (`shared-discovery.sh`,
`smoke.sh`) run `quickshell` with `QT_QPA_PLATFORM=offscreen`, so no window
opens.

CI ([`.github/workflows/test.yml`](../../.github/workflows/test.yml)) runs
`OMADROID_SKIP_QML=1 bash tests/run-all.sh` on Ubuntu: everything except the
two QML suites, which need quickshell and an installed Omarchy shell. That run
ends with `OMADROID_PARTIAL_OK`; run the full command locally before a
release.

The [README's Development section](../../README.md#development) describes what
each suite covers; [specs](../specs/) hold the contracts the tests check.

## Offscreen previews

To look at a view without opening a window, render it offscreen with the fake
devices:

```bash
dir="$(mktemp -d)"
OMADROID_PREVIEW_DIR="$dir" bash tests/smoke.sh
```

This writes one PNG per view into `$dir` (an absolute path outside the
checkout) and exits.

- `OMADROID_PREVIEW_PAGES` picks the views, comma-separated and in order:
  `home`, `add`, `settings`, `device` or `device-<part>` for the USB phone,
  `wifi` or `wifi-<part>` for the wireless one (part: `sound`, `info`, or
  `mirror` / `audio` / `webcam` with that card's options open), plus session
  steps such as `click-<kind>`, `start`, `record` and `stopped`. The full list
  is in `tests/Preview.qml`.
- `OMADROID_PREVIEW_QML=tests/HomePreview.qml` or `tests/DevicePreview.qml`
  swaps the capture script.
- `QT_SCALE_FACTOR=2` renders at twice the size (920 × 1800 px).
- Offscreen renders skip `MultiEffect`, and the popup uses the active Omarchy
  theme's colours.

Afterwards make sure nothing is left running, and kill your own leftovers:

```bash
pgrep -af omadroid-smoke
```

Never screenshot the desktop or inject input on the user's monitors for a
review. See [ADR 8](../adr/0008-offscreen-preview-harness.md).

## Refresh the preview

The README hero is [`preview.png`](../../preview.png) (3840 × 2160). Its
editable source is [`docs/brand/preview.svg`](../brand/preview.svg), which
places two offscreen captures from `docs/brand/captures/`. See
[branding](../branding.md) for colours and for how the SVG relates to the
shipped PNG.

1. Render the captures at 2× with the fake devices:

   ```bash
   dir="$(mktemp -d)"
   QT_SCALE_FACTOR=2 OMADROID_PREVIEW_PAGES=home,device-mirror \
     OMADROID_PREVIEW_DIR="$dir" bash tests/smoke.sh
   pgrep -af omadroid-smoke
   ```

2. Crop them to the part the hero shows and strip metadata:

   ```bash
   magick "$dir/0-home.png" -crop 920x1015+0+0 +repage -strip docs/brand/captures/home.png
   magick "$dir/1-device-mirror.png" -crop 920x1250+0+0 +repage -strip docs/brand/captures/device-mirror.png
   ```

3. Look at both captures: only fixture names (`Desk phone`, `Pixel 9`,
   `adb-NEW-…`, `USB123`) and fixture addresses may appear.
4. Render the hero from the repository root and look at the PNG before
   committing it:

   ```bash
   rsvg-convert -o preview.png docs/brand/preview.svg
   ```

The SVG asks for JetBrains Mono and falls back to DejaVu Sans Mono; a
different font changes text widths, so inspect the render. Keep the README's
alt text accurate when the panels change.

## Release

1. Bump `version` in `manifest.json` and turn `## Unreleased` in
   `CHANGELOG.md` into `## X.Y.Z — YYYY-MM-DD`.
2. Check the README covers the change.
3. `bash tests/run-all.sh` prints `OMADROID_ALL_OK`.
4. `omarchy plugin validate .` exits 0.
5. Commit `Release X.Y.Z`, then an annotated tag `vX.Y.Z`.
6. Ask the owner before pushing the commit or the tag, and before publishing a
   GitHub release.
