#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-smoke.XXXXXX)"
trap '[[ "$test_dir" == /tmp/droidlink-smoke.* ]] && rm -rf -- "$test_dir"' EXIT
if [[ -n "${DROIDLINK_PREVIEW_DIR:-}" ]]; then
  cp "$repo_dir/tests/Preview.qml" "$test_dir/shell.qml"
else
  cp "$repo_dir/tests/Smoke.qml" "$test_dir/shell.qml"
fi
mkdir "$test_dir/bin" "$test_dir/config"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
cp "$repo_dir/tests/mock-avahi-browse.sh" "$test_dir/bin/avahi-browse"
chmod +x "$test_dir/bin/adb" "$test_dir/bin/scrcpy" "$test_dir/bin/avahi-browse"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
ln -s "$repo_dir" "$test_dir/plugin"
test_status=0
PATH="$test_dir/bin:$PATH" XDG_CONFIG_HOME="$test_dir/config" DROIDLINK_TEST_ARGS="$test_dir/scrcpy-args" QT_QPA_PLATFORM=wayland timeout 12s quickshell -p "$test_dir/shell.qml" --no-color >"$test_dir/output" 2>&1 || test_status=$?
cat "$test_dir/output"
test "$test_status" -eq 0
if rg -i '(TypeError|ReferenceError|SyntaxError|is not a type|Cannot assign|Unable to assign|Binding loop|Failed to load configuration|DROIDLINK_TEST_FAILED)' "$test_dir/output"; then exit 1; fi
if [[ -n "${DROIDLINK_PREVIEW_DIR:-}" ]]; then
  rg -q DROIDLINK_PREVIEW_OK "$test_dir/output"
  exit 0
fi
rg -q DROIDLINK_SMOKE_OK "$test_dir/output"
rg -q -- '--no-audio' "$test_dir/scrcpy-args"
rg -q -- '--turn-screen-off' "$test_dir/scrcpy-args"
rg -q -- '--fullscreen' "$test_dir/scrcpy-args"
rg -q -- '--record=.*/DroidLink-USB123-.*\.mkv' "$test_dir/scrcpy-args"
rg -q 'Fixture profile' "$test_dir/config/omarchy/droidlink.ini"
