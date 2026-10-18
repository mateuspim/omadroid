#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-shared.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-shared.* ]] && rm -rf -- "$test_dir"' EXIT

mkdir "$test_dir/bin" "$test_dir/config" "$test_dir/runtime"
chmod 700 "$test_dir/runtime"
cp "$repo_dir/tests/SharedDiscovery.qml" "$test_dir/shell.qml"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-avahi-browse.sh" "$test_dir/bin/avahi-browse"
chmod +x "$test_dir/bin/adb" "$test_dir/bin/avahi-browse"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
ln -s "$repo_dir" "$test_dir/plugin"
: >"$test_dir/adb.log"

test_status=0
unset DISPLAY WAYLAND_DISPLAY
PATH="$test_dir/bin:$PATH" \
  XDG_CONFIG_HOME="$test_dir/config" \
  XDG_RUNTIME_DIR="$test_dir/runtime" \
  XDG_STATE_HOME="$test_dir/state" \
  OMADROID_ADB_LOG="$test_dir/adb.log" \
  OMADROID_REFRESH_MARKER="$test_dir/refresh.started" \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=xdgdesktopportal \
  QT_STYLE_OVERRIDE=Fusion \
  timeout 14s quickshell -p "$test_dir/shell.qml" --no-color >"$test_dir/output" 2>&1 || test_status=$?

sed -n '1,240p' "$test_dir/output"
test "$test_status" -eq 0
if rg -i '(TypeError|ReferenceError|SyntaxError|is not a type|Cannot assign|Unable to assign|Binding loop|Failed to load configuration|OMADROID_SHARED_TEST_FAILED)' "$test_dir/output"; then exit 1; fi
rg -q OMADROID_SHARED_TEST_OK "$test_dir/output"
# Two explicit refreshes (the second coalesced into a follow-up) poll adb;
# with track-devices running nothing else does.
if [[ "${OMADROID_TEST_CASE:-}" == no_track ]]; then
  test "$(rg -c '^track ' "$test_dir/adb.log" || echo 0)" -eq 0
  test "$(rg -c '^start initial ' "$test_dir/adb.log")" -ge 1
else
  test "$(rg -c '^track ' "$test_dir/adb.log")" -eq 1
  test "$(rg -c '^start initial ' "$test_dir/adb.log" || echo 0)" -eq 0
  test "$(rg -c '^start ' "$test_dir/adb.log")" -eq 2
fi
test "$(rg -c '^start ' "$test_dir/adb.log")" -eq "$(rg -c '^end ' "$test_dir/adb.log")"
! rg -q "^overlap$" "$test_dir/adb.log"
