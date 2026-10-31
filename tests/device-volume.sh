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
# Logs every awk's arguments, so a test can check device output never lands
# in a process listing.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/awk-args"\nexec %s "$@"\n' "$test_dir" "$(command -v awk)" >"$test_dir/bin/awk"
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH" XDG_CACHE_HOME="$test_dir/cache" OMADROID_TEST_ARGS="$test_dir/scrcpy-args"
export OMADROID_VOLUME_MOCK="$repo_dir/tests/mock-volume-adb.sh" OMADROID_VOLUME_DIR="$test_dir/device"
dev="$test_dir/device"
volume() { bash "$repo_dir/scripts/device-volume.sh" "$@"; }
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
# playing at app volume 10, Game Bar idle, a system player.
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
[[ "$(grep -v -e '^app ' -e '^naming ' <<<"$status")" == "$expected" ]] || fail "status head: $status"
# Game Bar has no scrcpy name, so its label is being read.
[[ "$(grep '^naming ' <<<"$status")" == 'naming 10085' ]] || fail "first naming lines: $status"
# Aliased streams (TTS here) aren't listed; system uids have no app row.
[[ "$(grep '^app ' <<<"$status" | sort)" == $'app 10085 paused 100 0 com.example.gamebar com.example.gamebar\napp 10360 playing 10 0 com.example.starship Starship: Demo Game' ]] ||
  fail "app rows: $(grep '^app ' <<<"$status")"
[[ "$(grep -c '^pull ' "$dev/log")" == 1 && "$(unexpected_calls)" == 0 ]] || fail "first status pulls framework.jar once: $(cat "$dev/log")"
volume status USB123 >/dev/null
[[ "$(grep -c '^pull ' "$dev/log")" == 1 ]] || fail "codes are cached per firmware"
[[ "$(grep -c '^pm list packages -U$' "$dev/log")" == 1 ]] || fail "app names are cached: $(grep -c '^pm list packages -U$' "$dev/log") full app lists"
# The installed-app list and the device's reply reach awk as files, never as
# arguments: app names, packages and uids stay out of process listings.
[[ -s "$test_dir/awk-args" ]] || fail "awk wrapper saw no calls"
! grep -qE 'Starship|starship|gamebar|10360|10085' "$test_dir/awk-args" || fail "device data in awk arguments: $(grep -E 'Starship|starship|gamebar|10360|10085' "$test_dir/awk-args" | head -c 300)"
# The cache is private: folders 700, files 600, and an older readable cache
# is tightened on the next status.
apps_dir="$test_dir/cache/omadroid/apps"
[[ "$(stat -c %a "$test_dir/cache/omadroid" "$apps_dir" "$test_dir/cache/omadroid/audio-codes" | sort -u)" == 700 ]] || fail "cache folders: $(stat -c '%a %n' "$test_dir/cache/omadroid" "$apps_dir")"
[[ "$(find "$test_dir/cache/omadroid" -type f -perm /077 | wc -l)" == 0 ]] || fail "readable cache files: $(find "$test_dir/cache/omadroid" -type f -perm /077)"
find "$test_dir/cache/omadroid" -type d -exec chmod 755 {} +
find "$test_dir/cache/omadroid" -type f -exec chmod 644 {} +
volume status USB123 >/dev/null
[[ "$(find "$test_dir/cache/omadroid" -perm /077 | wc -l)" == 0 ]] ||
  fail "an older cache is tightened: $(find "$test_dir/cache/omadroid" -printf '%m %P\n')"

# After a factory reset the cached uid belongs to another app: the name
# follows the package the device reports now, and the stale list is rebuilt.
apps_cache="$apps_dir/R5CR123ABC.tsv"
printf '10360\tcom.example.oldapp\tOld App\n10085\tcom.example.gamebar\tGame Bar\n' >"$apps_cache"
touch -d '1 hour ago' "$apps_cache"
# Only app players, so no system uid triggers the rebuild by accident.
cp -- "$dev/players" "$test_dir/players"
grep -v '^1000 ' "$test_dir/players" >"$dev/players"
[[ "$(volume status USB123 | grep '^app 10360')" == 'app 10360 playing 10 0 com.example.starship Starship: Demo Game' ]] ||
  fail "stale uid name after a reset: $(volume status USB123 | grep '^app ')"
grep -q 'com.example.starship' "$apps_cache" || fail "stale app list not rebuilt: $(cat "$apps_cache")"
# A system player (uid 1000) never has an app row, so it never rebuilds the list.
cp -- "$test_dir/players" "$dev/players"
: >"$dev/log"
touch -d '1 hour ago' "$apps_cache"
volume status USB123 >/dev/null
[[ "$(grep -c '^pm list packages -U$' "$dev/log")" == 0 ]] || fail "a system player rebuilt the app list"
# Even a fresh stale list (no rebuild yet) names the app by its package.
printf '10360\tcom.example.oldapp\tOld App\n' >"$apps_cache"
[[ "$(volume status USB123 | grep '^app 10360')" == 'app 10360 playing 10 0 com.example.starship com.example.starship' ]] ||
  fail "fresh stale list: $(volume status USB123 | grep '^app ')"
rm -f -- "$apps_cache"

# An app scrcpy doesn't name (no launcher icon, like a keyboard) shows its
# package, then the label read from its APK in the background, read once.
labels_dir="$test_dir/cache/omadroid/app-labels"
wait_for_labels() { sleep 0.1; flock "$labels_dir/R5CR123ABC.tsv.lock" true; }
mkdir -p "$dev/apks/com.example.keys"
python3 -I "$repo_dir/tests/make-apk.py" "$dev/apks/com.example.keys/Keys.apk" default
printf '10400 started\n' >>"$dev/players"
: >"$dev/log"
status="$(volume status USB123)"
[[ "$(grep '^app 10400' <<<"$status")" == 'app 10400 playing 100 0 com.example.keys com.example.keys' ]] ||
  fail "unnamed app before its label is read: $(grep '^app 10400' <<<"$status")"
# While its label is read, the status says so (the UI shows "reading name").
[[ "$(grep '^naming' <<<"$status")" == 'naming 10400' ]] || fail "naming line: $(grep '^naming' <<<"$status")"
wait_for_labels
[[ "$(volume status USB123)" != *naming* ]] || fail "naming after the label was read"
[[ "$(volume status USB123 | grep '^app 10400')" == 'app 10400 playing 100 0 com.example.keys Example Keys' ]] ||
  fail "APK label: $(volume status USB123 | grep '^app ') / $(cat "$labels_dir"/* 2>&1)"
# Game Bar has no APK here: recorded as failed by the earlier reads, so only
# the keyboard's APK was pulled since, once.
wait_for_labels
grep -qx com.example.gamebar "$labels_dir/R5CR123ABC.failed" || fail "failed label not recorded: $(ls "$labels_dir")"
[[ "$(grep -c '^shell -T$' "$dev/log")" == 1 ]] || fail "APKs pulled $(grep -c '^shell -T$' "$dev/log") times; expected 1"
[[ "$(find "$labels_dir" -type f -perm /077 | wc -l)" == 0 ]] || fail "readable label cache: $(find "$labels_dir" -printf '%m %P\n')"
! grep -qE 'example\.keys|Example Keys' "$test_dir/awk-args" || fail "app labels in awk arguments"
sed -i '/^10400 /d' "$dev/players"
# While a reader holds the lock, a read starts no second one but still says
# the name is being read; the status doesn't wait for the reader.
rm -f -- "$labels_dir/R5CR123ABC.failed"
flock "$labels_dir/R5CR123ABC.tsv.lock" sleep 2 &
sleep 0.2
started=$SECONDS
[[ "$(volume status USB123)" == *'naming 10085'* ]] || fail "naming while a reader runs"
((SECONDS - started < 2)) || fail "status waited for the running reader"
wait
sleep 0.3
[[ ! -e "$labels_dir/R5CR123ABC.failed" ]] || fail "a second reader started while one ran"

# Per-app volume and mute through the verified codes.
volume app USB123 10360 set 40 >/dev/null
[[ "$(cat "$dev/app-10360")" == 40 ]] || fail "app volume set"
volume app USB123 10360 mute >/dev/null
[[ "$(volume status USB123 | grep '^app 10360')" == 'app 10360 playing 40 1 com.example.starship Starship: Demo Game' ]] || fail "app muted"
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
[[ "$(grep '^app 10360' <<<"$status")" == 'app 10360 playing - 0 com.example.starship Starship: Demo Game' ]] || fail "plain app row: $status"
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
