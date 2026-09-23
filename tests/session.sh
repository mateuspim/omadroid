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
chmod +x "$test_dir/bin/omarchy" "$test_dir/bin/xdg-terminal-exec" "$test_dir/bin/scrcpy" "$test_dir/bin/adb"
export PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" DROIDLINK_TEST_ARGS="$test_dir/args"
test -z "$(bash "$repo_dir/session.sh" check)"
bash "$repo_dir/session.sh" launch USB123 0 '' -- scrcpy --serial=USB123 --max-size=3840 --max-fps=60 --video-bit-rate=60M --no-audio --max-fps=120
status="$(bash "$repo_dir/session.sh" status)"
[[ "$status" == $'active\nUSB123\n0\n'* ]]
if bash "$repo_dir/session.sh" launch USB123 0 '' -- scrcpy --serial=USB123 2>/dev/null; then
  echo 'Duplicate launch unexpectedly succeeded.' >&2
  exit 1
fi
rg -q -- '--max-size=3840' "$test_dir/args"
rg -q -- '--video-bit-rate=60M' "$test_dir/args"
bash "$repo_dir/session.sh" stop
for ((attempt=0; attempt<30; attempt++)); do
  [[ "$(bash "$repo_dir/session.sh" status)" == inactive ]] && break
  sleep 0.1
done
[[ "$(bash "$repo_dir/session.sh" status)" == inactive ]]
echo 'DROIDLINK_SESSION_OK'
