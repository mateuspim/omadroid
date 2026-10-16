#!/usr/bin/env bash
# The device side of device-volume.sh, called by mock-adb.sh through
# DROIDLINK_VOLUME_MOCK. Exits 100 for calls it doesn't handle.
#
# DROIDLINK_VOLUME_DIR holds the device: `fingerprint`, `framework.jar`,
# `stream-N` and `muted-N` per stream index, `app-UID`/`appmute-UID`
# (Samsung) and `appop-UID` (PLAY_AUDIO ignored), `master`, `ringer`
# (0-2), `players` ("UID started|idle" lines) and `log` of every call.
# Device scripts are evaluated with fake service/cmd/dumpsys/appops/input/pm,
# so the real script's quoting and parsing run. Service codes are the Tab
# S11's; DROIDLINK_TEST_CASE=wrong_codes answers getStreamVolume wrongly, as a
# device whose cached codes no longer match would.
set -u
export LC_ALL=C
dir="${DROIDLINK_VOLUME_DIR:?}"
[[ "${1:-}" == -s ]] || exit 100
serial="$2"
shift 2

value() { cat "$dir/$1" 2>/dev/null || printf '%s' "$2"; }
parcel() { printf "Result: Parcel(\t00000000 %08x   '........')\n" "$1"; }
void() { printf "Result: Parcel(\t00000000    '....')\n"; }

service() {
  [[ "$1 $2" == 'call audio' ]] || return 1
  shift 2
  printf 'service %s\n' "$*" >>"$dir/log"
  case "$1 ${*:2}" in
    '27 i32 '*) [[ "${DROIDLINK_TEST_CASE:-}" == wrong_codes ]] && parcel 99 || parcel "$(value "stream-$3" 0)" ;;
    '294 i32 '*) parcel "$(value "app-$3" 100)" ;;
    '296 i32 '*) parcel "$(value "appmute-$3" 0)" ;;
    '293 i32 '*' i32 '*' s16 com.android.shell') printf '%s' "$5" >"$dir/app-$3"; void ;;
    '295 i32 '*' i32 '[01]' s16 com.android.shell') printf '%s' "$5" >"$dir/appmute-$3"; void ;;
    '25 ') parcel "$(value master 0)" ;;
    '26 i32 '[01]' i32 0 s16 com.android.shell i32 0 i32 -1') printf '%s' "$3" >"$dir/master"; void ;;
    *) printf 'unexpected service call %s\n' "$*" >>"$dir/log"; printf "Result: Parcel(fffffffc 00000000 '........')\n" ;;
  esac
}

cmd() {
  printf 'cmd %s\n' "$*" >>"$dir/log"
  [[ "$1" == audio ]] || return 1
  case "$2" in
    get-stream-volume) printf 'AudioManager.getStreamVolume(%s) -> %s\n' "$3" "$(value "stream-$3" 0)" ;;
    set-volume) printf '%s' "$4" >"$dir/stream-$3" ;;
    adj-volume) local v; v="$(value "stream-$3" 0)"; [[ "$4" == RAISE ]] && v=$((v + 1)) || v=$((v - 1)); printf '%s' "$v" >"$dir/stream-$3" ;;
    adj-mute) printf 1 >"$dir/muted-$3" ;;
    adj-unmute) printf 0 >"$dir/muted-$3" ;;
    set-ringer-mode) case "$3" in SILENT) printf 0 ;; VIBRATE) printf 1 ;; NORMAL) printf 2 ;; esac >"$dir/ringer" ;;
    *) return 1 ;;
  esac
}

# Stream sections and players in the Tab S11's dumpsys format.
dumpsys() {
  local name index min
  [[ "$1" == audio ]] || return 1
  for name in 'VOICE_CALL|0|1' 'SYSTEM|1|0' 'RING|2|0' 'MUSIC|3|0' 'ALARM|4|1' 'NOTIFICATION|5|0' 'TTS (aliased to: STREAM_MUSIC)|9|0' 'ASSISTANT|11|0'; do
    IFS='|' read -r name index min <<<"$name"
    printf -- '- STREAM_%s:\n' "$name"
    printf '   Muted: %s\n   Muted Internally: false\n   Min: %s\n   Max: 15\n   streamVolume:%s\n' \
      "$([[ "$(value "muted-$index" 0)" == 1 ]] && echo true || echo false)" "$min" "$(value "stream-$index" 0)"
    printf '   Current: 2 (speaker): %s\n' "$(value "stream-$index" 0)"
  done
  printf 'Events log: App Volume\n'
  while read -r uid state; do
    printf '  AudioPlaybackConfiguration piid:%s deviceIds:[] type:AAudio u/pid:%s/1234 state:%s attr:AudioAttributes: usage=USAGE_GAME\n' "$RANDOM" "$uid" "$state"
  done <"$dir/players"
}

appops() {
  printf 'appops %s\n' "$*" >>"$dir/log"
  case "$1" in
    get) [[ -e "$dir/appop-$2" ]] && echo 'PLAY_AUDIO: ignore; time=+1s' || echo 'No operations.' ;;
    set) [[ "$4" == ignore ]] && touch "$dir/appop-$2" || rm -f "$dir/appop-$2" ;;
  esac
}

input() { printf 'input %s\n' "$*" >>"$dir/log"; }
settings() { [[ "$*" == 'get global mode_ringer' ]] && value ringer 2; }
pm() {
  printf 'pm %s\n' "$*" >>"$dir/log"
  printf '%s\n' 'package:android uid:1000' 'package:com.HoYoverse.hkrpgoversea uid:10360' 'package:com.samsung.android.game.gametools uid:10085' 'package:com.google.android.youtube uid:10200,10201'
}
getprop() {
  case "$1" in
    ro.build.fingerprint) echo "$(value fingerprint 'samsung/fixture:16/user')" ;;
    ro.serialno) echo R5CR123ABC ;;
  esac
}

case "$1" in
  pull)
    printf 'pull %s\n' "$2" >>"$dir/log"
    [[ "$2" == /system/framework/framework.jar ]] && cp -- "$dir/framework.jar" "$3"
    ;;
  shell)
    [[ "$2" =~ ro\.build\.fingerprint|service\ call\ audio|cmd\ audio|appops|KEYCODE_VOLUME|pm\ list\ packages\ -U|dumpsys\ audio ]] || exit 100
    [[ "$serial" != MISSING ]] || { printf "adb: device 'MISSING' not found\n" >&2; exit 1; }
    shift
    eval "$*" | sed 's/$/\r/'
    ;;
  *) exit 100 ;;
esac
