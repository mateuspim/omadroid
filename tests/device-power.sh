#!/usr/bin/env bash
# device-power.sh against fixtures: a fake keyring, a simulated lock screen and
# a keeper scrcpy. Nothing here touches a real device or the real keyring.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-power.XXXXXX)"
cleanup() {
  bash "$repo_dir/device-power.sh" keep-awake off USB123 >/dev/null 2>&1 || true
  [[ "$test_dir" == /tmp/omadroid-power.* ]] && rm -rf -- "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/bin" "$test_dir/runtime" "$test_dir/state" "$test_dir/keyring" "$test_dir/device"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
cp "$repo_dir/tests/mock-secret-tool.sh" "$test_dir/bin/secret-tool"
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" XDG_STATE_HOME="$test_dir/state"
export OMADROID_KEYRING="$test_dir/keyring" OMADROID_POWER_DIR="$test_dir/device" OMADROID_TEST_ARGS="$test_dir/scrcpy-args"
power() { bash "$repo_dir/device-power.sh" "$@"; }
fail() {
  echo "OMADROID_POWER_FAILED: $*" >&2
  exit 1
}
expect_code() {
  local expected="$1" code=0
  shift
  power "$@" >/dev/null 2>&1 || code=$?
  [[ "$code" == "$expected" ]] || fail "'$*' exited $code; expected $expected"
}
lock_device() {
  rm -f "$OMADROID_POWER_DIR/awake" "$OMADROID_POWER_DIR/typed"
  touch "$OMADROID_POWER_DIR/locked"
}
# Each odd password exercises one rule of the typing script.
password=$'it\'s 50%sale  $HOME;`id`\\'
printf '%s' "$password" >"$OMADROID_POWER_DIR/password"

[[ "$(power status USB123)" == 'keep=off running=0 secret=none' ]] || fail "initial status"
expect_code 1 status 'bad serial;'
lock_device
expect_code 3 unlock USB123
[[ -e "$OMADROID_POWER_DIR/locked" && ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "unlock without a secret typed something"
[[ -e "$OMADROID_POWER_DIR/awake" ]] || fail "unlock without a secret still wakes"

# Values `input text` can't type are refused at save time.
for invalid in 'abc' $'caf\xc3\xa9 1' ' lead' 'trail ' "$(printf 'x%.0s' {1..65})"; do
  printf '%s' "$invalid" | power secret-set USB123 >/dev/null 2>&1 && fail "accepted invalid secret '$invalid'"
done

printf '%s\n' "$password" | power secret-set USB123 >/dev/null
[[ "$(cat "$OMADROID_KEYRING/R5CR123ABC")" == "$password" ]] || fail "keyring holds the secret keyed by hardware serial"
[[ "$(power status USB123)" == 'keep=off running=0 secret=saved' ]] || fail "saved status"

# Correct secret: typed exactly, unlocked, no secret in any argv.
power unlock USB123 >/dev/null
[[ "$(cat "$OMADROID_POWER_DIR/typed")" == "$password" ]] || fail "typed '$(cat "$OMADROID_POWER_DIR/typed")'"
[[ ! -e "$OMADROID_POWER_DIR/locked" ]] || fail "device still locked"
! grep -qF -- 'HOME;`id`' "$OMADROID_POWER_DIR/argv" "$OMADROID_KEYRING/argv" || fail "secret leaked into argv"
[[ "$(power unlock USB123)" == 'Device is awake and unlocked.' ]] || fail "unlocked device"

# Another device (same adb serial reused) never receives this device's secret.
lock_device
expect_code 3 unlock OTHER1
[[ ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "secret typed into another device"

# An impostor reporting the right serial (it is broadcast over mDNS) but a
# different android_id is refused before typing, without spending the attempt.
lock_device
printf '00000000deadbeef' >"$OMADROID_POWER_DIR/android_id"
expect_code 6 unlock USB123
[[ ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "secret typed into a device with another android_id"
[[ "$(power status USB123)" == *secret=saved ]] || fail "identity refusal spent the attempt"
rm -f "$OMADROID_POWER_DIR/android_id"
! grep -qF 9f3a61c2d4e5b708 "$OMADROID_KEYRING/argv" "$XDG_STATE_HOME/omadroid/devices/R5CR123ABC/secret" || fail "raw android_id stored or passed in argv"

# A secret saved without an identity hash is refused until saved again.
saved_identity="$(cat "$XDG_STATE_HOME/omadroid/devices/R5CR123ABC/secret")"
: >"$XDG_STATE_HOME/omadroid/devices/R5CR123ABC/secret"
[[ "$(power unlock USB123 2>&1)" == *'Save the PIN again.' ]] || fail "missing identity hash not refused"
[[ ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "typed without an identity hash"
[[ "$(power status USB123)" == *secret=stale ]] || fail "a PIN without an identity is reported stale"
printf '%s\n' "$saved_identity" >"$XDG_STATE_HOME/omadroid/devices/R5CR123ABC/secret"

# Pattern lock or no bouncer: nothing typed, attempt not spent.
OMADROID_TEST_CASE=pattern expect_code 1 unlock USB123
[[ ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "typed into a pattern lock"
[[ "$(power status USB123)" == *secret=saved ]] || fail "pattern refusal spent the attempt"

# Wrong secret: one attempt, then paused until saved again.
printf 'wrong' >"$OMADROID_POWER_DIR/password"
expect_code 4 unlock USB123
[[ "$(power status USB123)" == *secret=blocked ]] || fail "failed try not blocked"
lock_device
expect_code 4 unlock USB123
[[ ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "retried after a failed attempt"
[[ -e "$OMADROID_POWER_DIR/awake" ]] || fail "a paused unlock still wakes the device"
# On connect a paused device is still woken, never retried.
lock_device
power connected 0 1 USB123 >/dev/null 2>&1 || true
[[ ! -e "$OMADROID_POWER_DIR/typed" ]] || fail "on-connect retried a paused unlock"
[[ -e "$OMADROID_POWER_DIR/awake" ]] || fail "on-connect wakes a paused device"
printf 'wrong' | power secret-set USB123 >/dev/null
[[ "$(power status USB123)" == *secret=saved ]] || fail "saving again clears the pause"
lock_device
power connected 0 1 USB123 >/dev/null
[[ ! -e "$OMADROID_POWER_DIR/locked" ]] || fail "on-connect unlock"

power secret-clear USB123 >/dev/null
[[ ! -e "$OMADROID_KEYRING/R5CR123ABC" && "$(power status USB123)" == *secret=none ]] || fail "secret-clear"
OMADROID_TEST_CASE=keyring_locked expect_code 5 secret-set USB123 <<<'1234'

# On connect without a secret: wake only.
lock_device
power connected 0 1 USB123 >/dev/null
[[ -e "$OMADROID_POWER_DIR/awake" && -e "$OMADROID_POWER_DIR/locked" ]] || fail "on-connect fallback wake"

# Lock: screen off and keyguard up; a lock delay or an ignored key is reported.
rm -f "$OMADROID_POWER_DIR/locked"
touch "$OMADROID_POWER_DIR/awake"
[[ "$(power lock USB123)" == 'Device locked.' ]] || fail "lock"
[[ ! -e "$OMADROID_POWER_DIR/awake" && -e "$OMADROID_POWER_DIR/locked" ]] || fail "lock leaves the screen off and locked"
[[ "$(power lock USB123)" == 'Device locked.' ]] || fail "locking an asleep device stays asleep"
rm -f "$OMADROID_POWER_DIR/locked"
touch "$OMADROID_POWER_DIR/awake"
[[ "$(OMADROID_TEST_CASE=lock_delay power lock USB123)" == *'lock delay.' ]] || fail "lock delay reported"
touch "$OMADROID_POWER_DIR/awake"
OMADROID_TEST_CASE=sleep_ignored expect_code 1 lock USB123
expect_code 1 lock 'bad serial;'

# Keep awake: remembered per device, one keeper, restarted on connect.
power keep-awake on USB123 >/dev/null
power keep-awake on USB123 >/dev/null
[[ "$(power status USB123)" == 'keep=on running=1 secret=none' ]] || fail "keeper running"
[[ "$(pgrep -fc -- '--serial=USB123 --no-video --no-audio --no-window --keep-active')" == 1 ]] || fail "exactly one keeper"
read -r keeper_pid _ <"$XDG_RUNTIME_DIR/omadroid-$UID/keepers/R5CR123ABC"
kill "$keeper_pid"
for ((attempt = 0; attempt < 20; attempt++)); do kill -0 "$keeper_pid" 2>/dev/null || break; sleep 0.1; done
[[ "$(power status USB123)" == 'keep=on running=0 secret=none' ]] || fail "dead keeper detected"
power connected 0 0 USB123 >/dev/null
[[ "$(power status USB123)" == 'keep=on running=1 secret=none' ]] || fail "keeper restarted on connect"
power keep-awake off USB123 >/dev/null
[[ "$(power status USB123)" == 'keep=off running=0 secret=none' ]] || fail "keeper stopped"
expect_code 1 keep-awake maybe USB123

echo OMADROID_POWER_OK
