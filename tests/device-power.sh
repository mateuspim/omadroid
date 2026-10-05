#!/usr/bin/env bash
# device-power.sh against fixtures: a fake keyring, a simulated lock screen and
# a keeper scrcpy. Nothing here touches a real device or the real keyring.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-power.XXXXXX)"
cleanup() {
  bash "$repo_dir/device-power.sh" keep-awake off USB123 >/dev/null 2>&1 || true
  [[ "$test_dir" == /tmp/droidlink-power.* ]] && rm -rf -- "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/bin" "$test_dir/runtime" "$test_dir/state" "$test_dir/keyring" "$test_dir/device"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
cp "$repo_dir/tests/mock-secret-tool.sh" "$test_dir/bin/secret-tool"
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" XDG_STATE_HOME="$test_dir/state"
export DROIDLINK_KEYRING="$test_dir/keyring" DROIDLINK_POWER_DIR="$test_dir/device" DROIDLINK_TEST_ARGS="$test_dir/scrcpy-args"
power() { bash "$repo_dir/device-power.sh" "$@"; }
fail() {
  echo "DROIDLINK_POWER_FAILED: $*" >&2
  exit 1
}
expect_code() {
  local expected="$1" code=0
  shift
  power "$@" >/dev/null 2>&1 || code=$?
  [[ "$code" == "$expected" ]] || fail "'$*' exited $code; expected $expected"
}
lock_device() {
  rm -f "$DROIDLINK_POWER_DIR/awake" "$DROIDLINK_POWER_DIR/typed"
  touch "$DROIDLINK_POWER_DIR/locked"
}
# Each odd password exercises one rule of the typing script.
password=$'it\'s 50%sale  $HOME;`id`\\'
printf '%s' "$password" >"$DROIDLINK_POWER_DIR/password"

[[ "$(power status USB123)" == 'keep=off running=0 secret=none' ]] || fail "initial status"
expect_code 1 status 'bad serial;'
lock_device
expect_code 3 unlock USB123
[[ -e "$DROIDLINK_POWER_DIR/locked" && ! -e "$DROIDLINK_POWER_DIR/typed" ]] || fail "unlock without a secret typed something"
[[ -e "$DROIDLINK_POWER_DIR/awake" ]] || fail "unlock without a secret still wakes"

# Values `input text` can't type are refused at save time.
for invalid in 'abc' $'caf\xc3\xa9 1' ' lead' 'trail ' "$(printf 'x%.0s' {1..65})"; do
  printf '%s' "$invalid" | power secret-set USB123 >/dev/null 2>&1 && fail "accepted invalid secret '$invalid'"
done

printf '%s\n' "$password" | power secret-set USB123 >/dev/null
[[ "$(cat "$DROIDLINK_KEYRING/R5CR123ABC")" == "$password" ]] || fail "keyring holds the secret keyed by hardware serial"
[[ "$(power status USB123)" == 'keep=off running=0 secret=saved' ]] || fail "saved status"

# Correct secret: typed exactly, unlocked, no secret in any argv.
power unlock USB123 >/dev/null
[[ "$(cat "$DROIDLINK_POWER_DIR/typed")" == "$password" ]] || fail "typed '$(cat "$DROIDLINK_POWER_DIR/typed")'"
[[ ! -e "$DROIDLINK_POWER_DIR/locked" ]] || fail "device still locked"
! grep -qF -- 'HOME;`id`' "$DROIDLINK_POWER_DIR/argv" "$DROIDLINK_KEYRING/argv" || fail "secret leaked into argv"
[[ "$(power unlock USB123)" == 'Device is awake and unlocked.' ]] || fail "unlocked device"

# Another device (same adb serial reused) never receives this device's secret.
lock_device
expect_code 3 unlock OTHER1
[[ ! -e "$DROIDLINK_POWER_DIR/typed" ]] || fail "secret typed into another device"

# Pattern lock or no bouncer: nothing typed, attempt not spent.
DROIDLINK_TEST_CASE=pattern expect_code 1 unlock USB123
[[ ! -e "$DROIDLINK_POWER_DIR/typed" ]] || fail "typed into a pattern lock"
[[ "$(power status USB123)" == *secret=saved ]] || fail "pattern refusal spent the attempt"

# Wrong secret: one attempt, then paused until saved again.
printf 'wrong' >"$DROIDLINK_POWER_DIR/password"
expect_code 4 unlock USB123
[[ "$(power status USB123)" == *secret=blocked ]] || fail "failed try not blocked"
lock_device
expect_code 4 unlock USB123
[[ ! -e "$DROIDLINK_POWER_DIR/typed" ]] || fail "retried after a failed attempt"
[[ -e "$DROIDLINK_POWER_DIR/awake" ]] || fail "a paused unlock still wakes the device"
# On connect a paused device is still woken, never retried.
lock_device
power connected 0 1 USB123 >/dev/null 2>&1 || true
[[ ! -e "$DROIDLINK_POWER_DIR/typed" ]] || fail "on-connect retried a paused unlock"
[[ -e "$DROIDLINK_POWER_DIR/awake" ]] || fail "on-connect wakes a paused device"
printf 'wrong' | power secret-set USB123 >/dev/null
[[ "$(power status USB123)" == *secret=saved ]] || fail "saving again clears the pause"
lock_device
power connected 0 1 USB123 >/dev/null
[[ ! -e "$DROIDLINK_POWER_DIR/locked" ]] || fail "on-connect unlock"

power secret-clear USB123 >/dev/null
[[ ! -e "$DROIDLINK_KEYRING/R5CR123ABC" && "$(power status USB123)" == *secret=none ]] || fail "secret-clear"
DROIDLINK_TEST_CASE=keyring_locked expect_code 5 secret-set USB123 <<<'1234'

# On connect without a secret: wake only.
lock_device
power connected 0 1 USB123 >/dev/null
[[ -e "$DROIDLINK_POWER_DIR/awake" && -e "$DROIDLINK_POWER_DIR/locked" ]] || fail "on-connect fallback wake"

# Keep awake: remembered per device, one keeper, restarted on connect.
power keep-awake on USB123 >/dev/null
power keep-awake on USB123 >/dev/null
[[ "$(power status USB123)" == 'keep=on running=1 secret=none' ]] || fail "keeper running"
[[ "$(pgrep -fc -- '--serial=USB123 --no-video --no-audio --no-window --keep-active')" == 1 ]] || fail "exactly one keeper"
read -r keeper_pid _ <"$XDG_RUNTIME_DIR/droidlink-$UID/keepers/R5CR123ABC"
kill "$keeper_pid"
for ((attempt = 0; attempt < 20; attempt++)); do kill -0 "$keeper_pid" 2>/dev/null || break; sleep 0.1; done
[[ "$(power status USB123)" == 'keep=on running=0 secret=none' ]] || fail "dead keeper detected"
power connected 0 0 USB123 >/dev/null
[[ "$(power status USB123)" == 'keep=on running=1 secret=none' ]] || fail "keeper restarted on connect"
power keep-awake off USB123 >/dev/null
[[ "$(power status USB123)" == 'keep=off running=0 secret=none' ]] || fail "keeper stopped"
expect_code 1 keep-awake maybe USB123

echo DROIDLINK_POWER_OK
