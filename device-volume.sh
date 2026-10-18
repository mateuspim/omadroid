#!/usr/bin/env bash
# Android volume over adb: system sound streams, per-app volume and mute,
# master mute, ringer mode and the volume keys.
#
#   status SERIAL                 → lines, see print_status
#   stream SERIAL NAME set N|raise|lower|mute|unmute
#   app SERIAL UID set N|mute|unmute
#   master SERIAL mute|unmute
#   ringer SERIAL normal|vibrate|silent
#   key SERIAL up|down|mute
#
# Samsung's per-app volume and Android's master mute have no shell command;
# they are `service call audio CODE` with codes read from the device's own
# framework.jar by audio-codes.py, cached per firmware, and checked against
# `cmd audio` on the device before every use. Without them, per-app control
# falls back to mute through the PLAY_AUDIO app op.
#
# Exit codes: 0 done, 1 adb or usage error, 6 the action needs codes that
# couldn't be read or didn't verify.
set -uo pipefail
export LC_ALL=C

script_dir="$(dirname -- "${BASH_SOURCE[0]}")"
source "$script_dir/adb-lib.sh"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/omadroid"
# Stream key → AudioManager.STREAM_* index. Aliased streams (TTS,
# accessibility, DTMF) follow media or ringtone, so they aren't listed.
declare -A stream_index=([call]=0 [system]=1 [ring]=2 [media]=3 [alarm]=4 [notification]=5 [assistant]=11)
declare -A codes=()

# --- Codes -------------------------------------------------------------------

# Prints "FINGERPRINT SERIALNO" of the device.
device_ids() {
  local reply
  reply="$(device_shell "$1" 4 'getprop ro.build.fingerprint; getprop ro.serialno')" || die 1 "Couldn't reach $1 over adb."
  [[ "$reply" =~ ^([[:graph:]]+)$'\n'([A-Za-z0-9._-]{1,64})$ ]] || die 1 "$1 reported build and serial '$reply'; expected a fingerprint line and a serial line."
  printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

codes_file() {
  printf '%s/audio-codes/%s' "$cache_root" "$(printf '%s' "$1" | sha256sum | cut -c1-32)"
}

# Pulls framework.jar once per firmware; a failure isn't cached, so a missing
# python3 or a dropped connection is retried on the next status.
read_codes() {
  local serial="$1" file="$2" work
  command -v python3 >/dev/null 2>&1 || return 1
  mkdir -p -- "${file%/*}"
  work="$(mktemp -d)" || return 1
  timeout 90 adb -s "$serial" pull /system/framework/framework.jar "$work/framework.jar" >/dev/null 2>&1 &&
    python3 -I "$script_dir/audio-codes.py" "$work/framework.jar" >"$work/codes" 2>"$work/error" &&
    mv -- "$work/codes" "$file"
  local status=$?
  rm -rf -- "$work"
  return "$status"
}

# Fills `codes` from the cache, reading them first if needed.
load_codes() {
  local file name code
  file="$(codes_file "$2")"
  if [[ ! -s "$file" ]]; then
    mkdir -p -- "${file%/*}"
    exec 9>"$file.lock"
    flock -x 9
    [[ -s "$file" ]] || read_codes "$1" "$file" || return 1
  fi
  while IFS='=' read -r name code; do
    [[ "$name" =~ ^[A-Za-z]+$ && "$code" =~ ^[0-9]{1,5}$ ]] && codes[$name]="$code"
  done <"$file"
  [[ -n "${codes[getStreamVolume]:-}" ]]
}

# Device-side helpers. `word CODE ARGS` prints a reply's first int as a
# decimal, or nothing for an exception; `call CODE ARGS` succeeds only on a
# reply without an exception (those start fffffff…). `verified` compares the
# cached getStreamVolume code with `cmd audio` before any other code is used.
device_preamble() {
  cat <<EOF
word() { w=\$(service call audio "\$@" | sed -n 's/.*Parcel([[:space:]]*00000000 \\([0-9a-f]\\{8\\}\\) .*/\\1/p'); [ -n "\$w" ] && echo \$((0x\$w)); }
call() { service call audio "\$@" | grep -q 'Parcel([[:space:]]*00000000'; }
verified() { [ -n "${codes[getStreamVolume]:-}" ] && [ "\$(word ${codes[getStreamVolume]:-0} i32 3)" = "\$(cmd audio get-stream-volume 3 | sed 's/.*-> //')" ]; }
EOF
}

has_codes() {
  local name
  for name in "$@"; do [[ -n "${codes[$name]:-}" ]] || return 1; done
}

per_app_mode() {
  has_codes getAppVolume setAppVolume isAppMute setAppMute && echo samsung || echo appops
}

# --- Status ------------------------------------------------------------------

# One adb shell: codes check, ringer, streams and players from dumpsys, then
# per-app volume and mute for every app uid that has a player.
status_script() {
  local mode="$1"
  device_preamble
  cat <<EOF
ok=0; verified && ok=1
echo "@verified \$ok"
echo "@ringer \$(settings get global mode_ringer)"
d=\$(dumpsys audio)
printf '%s\n' "\$d" | grep -E '^- STREAM_|^   (Muted|Min|Max|streamVolume):|AudioPlaybackConfiguration piid'
[ \$ok = 1 ] && [ -n "${codes[isMasterMute]:-}" ] && echo "@master \$(word ${codes[isMasterMute]:-0})"
for u in \$(printf '%s\n' "\$d" | sed -n 's/.*AudioPlaybackConfiguration piid:.* u\/pid:\([0-9]*\)\/.*/\1/p' | sort -u); do
  [ \$((u % 100000)) -ge 10000 ] && [ \$((u % 100000)) -lt 90000 ] || continue
  if [ "$mode" = samsung ]; then
    [ \$ok = 1 ] && echo "@app \$u \$(word ${codes[getAppVolume]:-0} i32 \$u) \$(word ${codes[isAppMute]:-0} i32 \$u)"
  else
    echo "@app \$u - \$(appops get \$u PLAY_AUDIO | grep -c -E 'PLAY_AUDIO: (ignore|deny|errored)')"
  fi
done
EOF
}

# Turns the device's dumpsys lines into "stream KEY INDEX VOLUME MIN MAX MUTED"
# and players into "player UID playing|paused" (playing if any player started).
parse_dumpsys() {
  awk '
    BEGIN { split("VOICE_CALL call 0 SYSTEM system 1 RING ring 2 MUSIC media 3 ALARM alarm 4 NOTIFICATION notification 5 ASSISTANT assistant 11", t, " ")
            for (i = 1; i in t; i += 3) { key[t[i]] = t[i + 1]; idx[t[i]] = t[i + 2] } }
    function flush() { if (name != "" && vol != "") print "stream", key[name], idx[name], vol, min, max, muted; name = "" }
    /^- STREAM_/ { flush(); n = $2; sub(/^STREAM_/, "", n); sub(/:$/, "", n); name = ($3 == "" && (n in key)) ? n : ""; vol = ""; next }
    name != "" && $1 == "Muted:" { muted = ($2 == "true") }
    name != "" && $1 == "Min:" { min = $2 }
    name != "" && $1 == "Max:" { max = $2 }
    name != "" && $1 ~ /^streamVolume:/ { vol = substr($1, 14) }
    /AudioPlaybackConfiguration piid/ && match($0, /u\/pid:[0-9]+/) {
      uid = substr($0, RSTART + 6, RLENGTH - 6)
      if ($0 ~ / state:started /) playing[uid] = 1; else if (!(uid in playing)) playing[uid] = 0
    }
    END { flush(); for (uid in playing) print "player", uid, playing[uid] ? "playing" : "paused" }
  '
}

apps_file() {
  printf '%s/apps/%s.tsv' "$cache_root" "$1"
}

# "APPID PACKAGE LABEL" for every package: uids from `pm`, labels from
# `scrcpy --list-apps` (packages without a launcher keep their package name).
read_apps() {
  local serial="$1" file="$2" packages labels
  packages="$(device_shell "$serial" 10 'pm list packages -U')" || return 1
  labels="$(timeout 20 scrcpy "--serial=$serial" --list-apps 2>/dev/null)" || labels=""
  mkdir -p -- "${file%/*}"
  awk -v labels="$labels" '
    BEGIN { n = split(labels, rows, "\n")
            for (i = 1; i <= n; i++) if (rows[i] ~ /^ [*-] /) { p = rows[i]; sub(/.* /, "", p); l = substr(rows[i], 4); sub(/ +[^ ]+$/, "", l); label[p] = l } }
    match($0, /^package:[^ ]+ uid:[0-9]+/) {
      split(substr($0, 9), f, " uid:"); u = f[2] + 0
      if (!((u % 100000) in seen)) { seen[u % 100000] = 1; print (u % 100000) "\t" f[1] "\t" ((f[1] in label) ? label[f[1]] : f[1]) }
    }' <<<"$packages" >"$file.new" && mv -- "$file.new" "$file"
}

# Rebuilt when a playing app is unknown, at most every 10 minutes: isolated
# and sandbox uids never appear in `pm`.
refresh_apps() {
  local serial="$1" file="$2" uid
  shift 2
  for uid in "$@"; do
    [[ -s "$file" ]] && awk -F'\t' -v id="$((uid % 100000))" '$1 == id { found = 1 } END { exit !found }' "$file" && continue
    [[ -s "$file" && -n "$(find "$file" -mmin -10 2>/dev/null)" ]] && return 0
    read_apps "$serial" "$file"
    return 0
  done
}

# mode samsung|appops · master 0|1|- · ringer normal|vibrate|silent|-
# stream KEY INDEX VOLUME MIN MAX MUTED · app UID playing|paused VOLUME|- MUTED|- PACKAGE LABEL
print_status() {
  local serial="$1" fingerprint serialno mode reply parsed file
  read -r fingerprint serialno <<<"$(device_ids "$serial")"
  load_codes "$serial" "$fingerprint"
  mode="$(per_app_mode)"
  reply="$(device_shell "$serial" 10 "$(status_script "$mode")")" || die 1 "Couldn't read the volume of $serial."
  [[ "$reply" == *'@verified 1'* ]] || mode=appops
  parsed="$(parse_dumpsys <<<"$reply")"
  file="$(apps_file "$serialno")"
  refresh_apps "$serial" "$file" $(awk '$1 == "player" { print $2 }' <<<"$parsed")
  printf 'mode %s\n' "$mode"
  awk '$1 == "@master" { m = ($2 == "1" || $2 == "0") ? $2 : "-" } END { print "master", m == "" ? "-" : m }' <<<"$reply"
  awk '$1 == "@ringer" { r = $2 == "0" ? "silent" : $2 == "1" ? "vibrate" : $2 == "2" ? "normal" : "-" } END { print "ringer", r == "" ? "-" : r }' <<<"$reply"
  grep '^stream ' <<<"$parsed"
  join_apps "$file" "$reply" "$parsed"
}

# One line per app player, volume and mute from @app, names from the cache.
join_apps() {
  awk -F'\t' -v reply="$2" -v parsed="$3" '
    BEGIN { n = split(reply, r, "\n"); for (i = 1; i <= n; i++) if (split(r[i], f, " ") >= 2 && f[1] == "@app") { vol[f[2]] = f[3]; mute[f[2]] = f[4] }
            n = split(parsed, p, "\n"); for (i = 1; i <= n; i++) if (split(p[i], f, " ") == 3 && f[1] == "player") state[f[2]] = f[3] }
    { pkg[$1] = $2; label[$1] = $3 }
    END { for (u in state) {
            id = u % 100000; if (id < 10000 || id >= 90000) continue
            v = (vol[u] ~ /^[0-9]+$/ && vol[u] <= 100) ? vol[u] : "-"; m = (mute[u] == "0" || mute[u] == "1") ? mute[u] : "-"
            print "app", u, state[u], v, m, (id in pkg) ? pkg[id] : "uid" u, (id in label) ? label[id] : "App " u } }
  ' "$([[ -s "$1" ]] && echo "$1" || echo /dev/null)"
}

# --- Actions -----------------------------------------------------------------

# Runs device commands and expects "@done" last; anything else is an error.
run_on_device() {
  local serial="$1" reply
  reply="$(device_shell "$serial" 8 "$2")" || die 1 "Couldn't reach $serial over adb."
  [[ "$reply" == *'@done' ]] || die 1 "$serial refused '$3': ${reply:-no reply}"
}

# Loads the codes for SERIAL and checks the named ones are there.
need_codes() {
  local serial="$1" fingerprint
  shift
  read -r fingerprint _ <<<"$(device_ids "$serial")"
  load_codes "$serial" "$fingerprint" && has_codes "$@" ||
    die 6 "Per-app volume and mute all need audio codes read from $serial's framework, which failed (is python3 installed?)."
}

# Runs `call …` lines only after the codes verify, in the same adb shell.
run_verified() {
  local reply
  reply="$(device_shell "$1" 8 "$(device_preamble)
verified || { echo @unverified; exit 0; }
$2 && echo @done")" || die 1 "Couldn't reach $1 over adb."
  [[ "$reply" != *'@unverified'* ]] || die 6 "The cached audio codes don't match $1's firmware; nothing was changed."
  [[ "$reply" == *'@done' ]] || die 1 "$1 refused '$3': ${reply:-no reply}"
}

set_stream() {
  local serial="$1" name="$2" action="$3" value="${4:-}" index
  index="${stream_index[$name]:-}"
  [[ -n "$index" ]] || die 1 "Unknown stream '$name'; expected one of: ${!stream_index[*]}."
  case "$action" in
    set) [[ "$value" =~ ^[0-9]{1,3}$ ]] || die 1 "stream set takes a volume 0-999, got '$value'."
      run_on_device "$serial" "cmd audio set-volume $index $value >/dev/null && echo @done" "$name $action $value" ;;
    raise | lower) run_on_device "$serial" "cmd audio adj-volume $index ${action^^} >/dev/null && echo @done" "$name $action" ;;
    mute | unmute) run_on_device "$serial" "cmd audio adj-$action $index >/dev/null && echo @done" "$name $action" ;;
    *) die 1 "stream takes set N|raise|lower|mute|unmute, got '$action'." ;;
  esac
}

# Samsung's app volume is 0-100; other phones can only mute an app.
set_app() {
  local serial="$1" uid="$2" action="$3" value="${4:-}" fingerprint mute
  [[ "$uid" =~ ^[0-9]{5,7}$ ]] || die 1 "Unexpected app uid '$uid'; expected 5-7 digits."
  read -r fingerprint _ <<<"$(device_ids "$serial")"
  load_codes "$serial" "$fingerprint"
  if [[ "$(per_app_mode)" != samsung ]]; then
    [[ "$action" == mute || "$action" == unmute ]] || die 6 "This device only supports muting apps, not app volume."
    [[ "$action" == mute ]] && mute=ignore || mute=allow
    run_on_device "$serial" "appops set $uid PLAY_AUDIO $mute && echo @done" "app $uid $action"
    return
  fi
  case "$action" in
    set) [[ "$value" =~ ^[0-9]{1,3}$ && "$value" -le 100 ]] || die 1 "app set takes a volume 0-100, got '$value'."
      run_verified "$serial" "call ${codes[setAppVolume]} i32 $uid i32 $value s16 com.android.shell" "app $uid set $value" ;;
    mute | unmute) [[ "$action" == mute ]] && mute=1 || mute=0
      run_verified "$serial" "call ${codes[setAppMute]} i32 $uid i32 $mute s16 com.android.shell" "app $uid $action" ;;
    *) die 1 "app takes set N|mute|unmute, got '$action'." ;;
  esac
}

# setMasterMute(mute, flags, callingPackage, userId, attributionTag = null).
set_master() {
  local serial="$1" mute
  case "$2" in
    mute) mute=1 ;;
    unmute) mute=0 ;;
    *) die 1 "master takes mute|unmute, got '$2'." ;;
  esac
  need_codes "$serial" setMasterMute isMasterMute
  run_verified "$serial" "call ${codes[setMasterMute]} i32 $mute i32 0 s16 com.android.shell i32 0 i32 -1" "master $2"
}

set_ringer() {
  [[ "$2" =~ ^(normal|vibrate|silent)$ ]] || die 1 "ringer takes normal|vibrate|silent, got '$2'."
  run_on_device "$1" "cmd audio set-ringer-mode ${2^^} >/dev/null && echo @done" "ringer $2"
}

press_key() {
  [[ "$2" =~ ^(up|down|mute)$ ]] || die 1 "key takes up|down|mute, got '$2'."
  run_on_device "$1" "input keyevent KEYCODE_VOLUME_${2^^} && echo @done" "key $2"
}

command="${1:-}"
shift || true
valid_serial "${1:-}"
case "$command" in
  status) print_status "$1" ;;
  stream) set_stream "$1" "${2:-}" "${3:-}" "${4:-}" ;;
  app) set_app "$1" "${2:-}" "${3:-}" "${4:-}" ;;
  master) set_master "$1" "${2:-}" ;;
  ringer) set_ringer "$1" "${2:-}" ;;
  key) press_key "$1" "${2:-}" ;;
  *) die 1 "Usage: device-volume.sh status|stream|app|master|ringer|key SERIAL …; got '$command'." ;;
esac
