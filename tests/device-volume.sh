#!/usr/bin/env bash
# device-volume.sh against a fake device (tests/mock-volume-adb.sh) whose
# framework.jar is a fixture dex. Nothing here touches a real device.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-volume.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-volume.* ]] && rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/cache" "$test_dir/device"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH" XDG_CACHE_HOME="$test_dir/cache" OMADROID_TEST_ARGS="$test_dir/scrcpy-args"
export OMADROID_VOLUME_MOCK="$repo_dir/tests/mock-volume-adb.sh" OMADROID_VOLUME_DIR="$test_dir/device"
dev="$test_dir/device"
volume() { bash "$repo_dir/device-volume.sh" "$@"; }
fail() {
  echo "OMADROID_VOLUME_FAILED: $*" >&2
  exit 1
}
expect_code() {
  local expected="$1" code=0
  shift
  volume "$@" >/dev/null 2>&1 || code=$?
  [[ "$code" == "$expected" ]] || fail "'$*' exited $code; expected $expected"
}
# A fresh device: Tab S11 codes, media 13/15, ringer on vibrate, the game
# playing at app volume 10, Game Tools idle, a system player.
reset_device() {
  rm -rf "${dev:?}"/*
  python3 -I "$repo_dir/tests/make-audio-dex.py" "$dev/framework.jar" "${1:-samsung}"
  printf '%s' "samsung/${1:-samsung}:16/user" >"$dev/fingerprint"
  printf 13 >"$dev/stream-3"; printf 9 >"$dev/stream-0"; printf 11 >"$dev/stream-4"; printf 7 >"$dev/stream-11"
  printf 1 >"$dev/muted-2"; printf 1 >"$dev/ringer"; printf 10 >"$dev/app-10360"
  printf '%s\n' '10360 started' '10360 idle' '10085 idle' '1000 idle' >"$dev/players"
  : >"$dev/log"
}
unexpected_calls() { grep -c 'unexpected' "$dev/log" || true; }

reset_device
status="$(volume status USB123)"
expected='mode samsung
master 0
ringer vibrate
stream call 0 9 1 15 0
stream system 1 0 0 15 0
stream ring 2 0 0 15 1
stream media 3 13 0 15 0
stream alarm 4 11 1 15 0
stream notification 5 0 0 15 0
stream assistant 11 7 0 15 0'
[[ "$(grep -v '^app ' <<<"$status")" == "$expected" ]] || fail "status head: $status"
# Aliased streams (TTS here) aren't listed; system uids have no app row.
[[ "$(grep '^app ' <<<"$status" | sort)" == $'app 10085 paused 100 0 com.samsung.android.game.gametools com.samsung.android.game.gametools\napp 10360 playing 10 0 com.HoYoverse.hkrpgoversea Honkai: Star Rail' ]] ||
  fail "app rows: $(grep '^app ' <<<"$status")"
[[ "$(grep -c '^pull ' "$dev/log")" == 1 && "$(unexpected_calls)" == 0 ]] || fail "first status pulls framework.jar once: $(cat "$dev/log")"
volume status USB123 >/dev/null
[[ "$(grep -c '^pull ' "$dev/log")" == 1 ]] || fail "codes are cached per firmware"
[[ "$(grep -c '^pm ' "$dev/log")" == 1 ]] || fail "app names are cached: $(grep -c '^pm ' "$dev/log") pm calls"

# Per-app volume and mute through the verified codes.
volume app USB123 10360 set 40 >/dev/null
[[ "$(cat "$dev/app-10360")" == 40 ]] || fail "app volume set"
volume app USB123 10360 mute >/dev/null
[[ "$(volume status USB123 | grep '^app 10360')" == 'app 10360 playing 40 1 com.HoYoverse.hkrpgoversea Honkai: Star Rail' ]] || fail "app muted"
volume app USB123 10360 unmute >/dev/null
[[ "$(cat "$dev/appmute-10360")" == 0 ]] || fail "app unmuted"
expect_code 1 app USB123 10360 set 101
expect_code 1 app USB123 '10360;reboot' set 5
expect_code 1 app USB123 10360 louder

# Master mute, streams, ringer and keys.
volume master USB123 mute >/dev/null
[[ "$(volume status USB123 | grep '^master')" == 'master 1' ]] || fail "master muted"
volume master USB123 unmute >/dev/null
[[ "$(cat "$dev/master")" == 0 ]] || fail "master unmuted"
volume stream USB123 media set 5 >/dev/null
volume stream USB123 media raise >/dev/null
[[ "$(cat "$dev/stream-3")" == 6 ]] || fail "media set then raised: $(cat "$dev/stream-3")"
volume stream USB123 ring unmute >/dev/null
[[ "$(cat "$dev/muted-2")" == 0 ]] || fail "ringtone unmuted"
volume ringer USB123 normal >/dev/null
[[ "$(volume status USB123 | grep '^ringer')" == 'ringer normal' ]] || fail "ringer mode"
volume key USB123 up >/dev/null
grep -qx 'input keyevent KEYCODE_VOLUME_UP' "$dev/log" || fail "volume key"
expect_code 1 stream USB123 bass set 3
expect_code 1 stream USB123 media set loud
expect_code 1 ringer USB123 loud
expect_code 1 key USB123 left
expect_code 1 status 'bad serial;'
expect_code 1 status MISSING
[[ "$(unexpected_calls)" == 0 ]] || fail "only known codes were called: $(grep unexpected "$dev/log")"

# Codes that don't verify are never used: status falls back, writes refuse.
: >"$dev/log"
status="$(OMADROID_TEST_CASE=wrong_codes volume status USB123)"
[[ "$status" == *'mode appops'* && "$status" == *'master -'* ]] || fail "unverified codes still offered: $status"
[[ "$(grep -c '^service ' "$dev/log")" == 1 ]] || fail "only the check code ran: $(grep '^service ' "$dev/log")"
printf 10 >"$dev/app-10360"
OMADROID_TEST_CASE=wrong_codes expect_code 6 app USB123 10360 set 80
OMADROID_TEST_CASE=wrong_codes expect_code 6 master USB123 mute
[[ "$(cat "$dev/app-10360")" == 10 && "$(cat "$dev/master" 2>/dev/null || echo 0)" == 0 ]] || fail "an unverified write changed something"

# A phone without Samsung's app volume mutes apps through PLAY_AUDIO.
reset_device plain
status="$(volume status USB123)"
[[ "$status" == *'mode appops'* && "$status" == *'master 0'* ]] || fail "plain phone status: $status"
[[ "$(grep '^app 10360' <<<"$status")" == 'app 10360 playing - 0 com.HoYoverse.hkrpgoversea Honkai: Star Rail' ]] || fail "plain app row: $status"
volume app USB123 10360 mute >/dev/null
[[ -e "$dev/appop-10360" && "$(volume status USB123 | grep '^app 10360')" == *' - 1 '* ]] || fail "app op mute"
volume app USB123 10360 unmute >/dev/null
[[ ! -e "$dev/appop-10360" ]] || fail "app op unmute"
expect_code 6 app USB123 10360 set 50

# Without python3 there are no codes; streams and app-op mute still work.
reset_device
rm -rf "$test_dir/cache/omadroid/audio-codes"
mkdir -p "$test_dir/nopython"
find /usr/bin -maxdepth 1 ! -name 'python*' -exec ln -s -t "$test_dir/nopython" {} +
status="$(PATH="$test_dir/bin:$test_dir/nopython" volume status USB123)"
[[ "$status" == *'mode appops'* && "$status" == *'stream media 3 13 0 15 0'* && "$(grep -c '^pull ' "$dev/log")" == 0 ]] || fail "status without python3: $status"

echo OMADROID_VOLUME_OK
