#!/usr/bin/env bash
# app-labels.sh against a hostile fake device (tests/mock-volume-adb.sh): the
# host-side pull cap, the parser timeout, cleanup when the run is stopped,
# and the tighten-only limit overrides (omacom/omarchy-plugin-marketplace#13776).
# Nothing here touches a real device.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-labels.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-labels.* ]] && rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/slow-python" "$test_dir/cache" "$test_dir/device/apks/com.example.keys"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
# A parser that never finishes, for the timeout.
printf '#!/usr/bin/env bash\nexec sleep 30\n' >"$test_dir/slow-python/python3"
chmod +x "$test_dir/bin/adb" "$test_dir/slow-python/python3"
export PATH="$test_dir/bin:$PATH" XDG_CACHE_HOME="$test_dir/cache"
export OMADROID_VOLUME_MOCK="$repo_dir/tests/mock-volume-adb.sh" OMADROID_VOLUME_DIR="$test_dir/device"
dev="$test_dir/device"
labels_dir="$test_dir/cache/omadroid/app-labels"
python3 -I "$repo_dir/tests/make-apk.py" "$dev/apks/com.example.keys/Keys.apk" default
fail() {
  echo "OMADROID_LABELS_FAILED: $*" >&2
  exit 1
}
# Runs app-labels.sh for the keyboard from a clean cache; fails past LIMIT s.
read_keys() {
  local limit="$1" started=$SECONDS
  shift
  rm -rf -- "$labels_dir" "$dev/apk-"*
  : >"$dev/log"
  printf 'com.example.keys\n' | "$@" bash "$repo_dir/scripts/app-labels.sh" USB123 R5CR123ABC || true
  ((SECONDS - started <= limit)) || fail "'${*:1:2}' took $((SECONDS - started)) s; expected at most $limit"
}
# The run left no work folder and holds no lock.
expect_clean() {
  [[ -z "$(find "$labels_dir" -name '.work-*' 2>/dev/null)" ]] || fail "$1: work folder left: $(ls -A "$labels_dir")"
  flock -n "$labels_dir/R5CR123ABC.tsv.lock" true || fail "$1: lock still held"
}
expect_failed() {
  grep -qx com.example.keys "$labels_dir/R5CR123ABC.failed" 2>/dev/null || fail "$1: not recorded as failed: $(ls -A "$labels_dir")"
  expect_clean "$1"
}

read_keys 10 env
[[ "$(cat "$labels_dir/R5CR123ABC.tsv")" == $'com.example.keys\tExample Keys' ]] || fail "label: $(cat "$labels_dir"/*)"
expect_clean 'a normal read'

# An endless stream stops at the host cap (1 MiB here) and is refused: the
# host closes the pipe (SIGPIPE, 141). The 4 MiB file-size limit keeps a
# regression from filling the disk; it would end the stream with SIGXFSZ.
read_keys 10 env OMADROID_LABEL_MAX_BYTES=1048576 bash -c 'ulimit -f 4096; touch "$OMADROID_VOLUME_DIR/apk-endless"; exec "$@"' sh
grep -qx 'endless stopped 141' "$dev/log" || fail "the endless pull wasn't cut by the host cap: $(cat "$dev/log")"
expect_failed 'an endless stream'

# A parser that hangs is stopped after the parse timeout (1 s here).
read_keys 8 env OMADROID_LABEL_PARSE_SECONDS=1 PATH="$test_dir/slow-python:$PATH"
expect_failed 'a hung parser'

# Stopped as device-volume.sh's timeout stops it (TERM to its process group)
# while adb hangs, the run removes its work folder at once.
read_keys 4 sh -c 'touch "$OMADROID_VOLUME_DIR/apk-hang"; exec timeout -k 5 1 "$@"' sh
sleep 0.5
grep -qx 'hang stopped' "$dev/log" || fail "the hung adb wasn't stopped with the run: $(cat "$dev/log")"
! grep -qx 'lock inherited' "$dev/log" || fail "adb inherited the run's lock"
expect_clean 'a stopped run'

# A run that was KILLed leaves its folder; the next one removes it.
rm -f -- "$dev/apk-"*
mkdir -p "$labels_dir/.work-killed"
printf 'com.example.keys\n' | bash "$repo_dir/scripts/app-labels.sh" USB123 R5CR123ABC
expect_clean 'after a killed run'

# Overrides only tighten a limit.
source "$repo_dir/scripts/app-cache-lib.sh"
[[ "$(at_most 5 30)" == 5 && "$(at_most 99 30)" == 30 && "$(at_most '' 30)" == 30 && "$(at_most '-1' 30)" == 30 && "$(at_most 0 30)" == 30 && "$(at_most '1;x' 30)" == 30 ]] ||
  fail "at_most: $(at_most 5 30) $(at_most 99 30) $(at_most '' 30) $(at_most -1 30) $(at_most 0 30)"

echo OMADROID_LABELS_OK
