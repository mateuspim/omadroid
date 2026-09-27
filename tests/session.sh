#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-session.XXXXXX)"
cleanup() {
  XDG_RUNTIME_DIR="$test_dir/runtime" bash "$repo_dir/session.sh" stop >/dev/null 2>&1 || true
  [[ "$test_dir" == /tmp/droidlink-session.* ]] && rm -rf -- "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/bin" "$test_dir/runtime"
cp "$repo_dir/tests/mock-omarchy.sh" "$test_dir/bin/omarchy"
cp "$repo_dir/tests/mock-xdg-terminal-exec.sh" "$test_dir/bin/xdg-terminal-exec"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-hyprctl.sh" "$test_dir/bin/hyprctl"
chmod +x "$test_dir/bin/omarchy" "$test_dir/bin/xdg-terminal-exec" "$test_dir/bin/scrcpy" "$test_dir/bin/adb" "$test_dir/bin/hyprctl"
export PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" DROIDLINK_TEST_ARGS="$test_dir/args"
export DROIDLINK_ADB_ROTATION="$test_dir/rotation" DROIDLINK_HYPRCTL_LOG="$test_dir/hyprctl"
session() { bash "$repo_dir/session.sh" "$@"; }
launch_long_session() {
  session launch USB123 0 '' -- scrcpy --serial=USB123 --max-size=3840 --max-fps=60 --video-bit-rate=60M --no-audio --max-fps=120
}
# The release after a session ends is detached, so poll for the device state.
wait_for_rotation() {
  for ((attempt=0; attempt<30; attempt++)); do
    [[ "$(cat "$DROIDLINK_ADB_ROTATION")" == "$1" ]] && return 0
    sleep 0.1
  done
  echo "Rotation state is $(cat "$DROIDLINK_ADB_ROTATION" | tr '\n' ' '); expected ${1//$'\n'/ }." >&2
  return 1
}
wait_for_inactive() {
  for ((attempt=0; attempt<30; attempt++)); do
    [[ "$(session status)" == inactive ]] && return 0
    sleep 0.1
  done
  return 1
}
test -z "$(bash "$repo_dir/session.sh" check)"
if session rotate query 2>/dev/null; then
  echo 'Rotation query without a session unexpectedly succeeded.' >&2
  exit 1
fi
launch_long_session
status="$(bash "$repo_dir/session.sh" status)"
[[ "$status" == $'active\nUSB123\n0\n'* ]]
if bash "$repo_dir/session.sh" launch USB123 0 '' -- scrcpy --serial=USB123 2>/dev/null; then
  echo 'Duplicate launch unexpectedly succeeded.' >&2
  exit 1
fi
# The terminal is hidden by a named rule registered before it opens.
[[ "$(cat "$test_dir/hyprctl")" == 'eval hl.window_rule({ name = "droidlink-terminal", match = { class = "^org\\.omarchy\\.droidlink$" }, workspace = "special:droidlink silent", no_initial_focus = true })' ]]
rg -q -- '--max-size=3840' "$test_dir/args"
rg -q -- '--video-bit-rate=60M' "$test_dir/args"

# A lock DroidLink sets is owned and released when the session stops.
for invalid in 'lock 4' 'lock' 'spin'; do
  if session rotate $invalid 2>/dev/null; then
    echo "Invalid rotate request '$invalid' unexpectedly succeeded." >&2
    exit 1
  fi
done
[[ "$(session rotate query)" == free ]]
session rotate lock 1
[[ "$(session rotate query)" == $'lock 1\nowned' ]]
session stop
wait_for_inactive
wait_for_rotation $'1\n0'

# Auto rotate / reset drops ownership, so a later stop sends nothing.
launch_long_session
session rotate lock 3
session rotate free
[[ "$(session rotate query)" == free ]]
[[ ! -e "$XDG_RUNTIME_DIR/droidlink-$UID/rotation" ]]
session stop
wait_for_inactive

# A lock chosen on the phone is reported but survives the session.
printf '0\n2\n' > "$DROIDLINK_ADB_ROTATION"
launch_long_session
[[ "$(session rotate query)" == 'lock 2' ]]
session stop
wait_for_inactive
sleep 0.3
wait_for_rotation $'0\n2'

# A session that dies without stop (window closed, crash) is released by status.
launch_long_session
session rotate lock 0
pid="$(session status | sed -n 5p)"
kill -KILL "$pid"
wait_for_inactive
wait_for_rotation $'1\n0'
echo 'DROIDLINK_SESSION_OK'
