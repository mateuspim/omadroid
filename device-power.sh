#!/usr/bin/env bash
# Keep Android devices awake, wake them, and unlock them with a secret kept in
# the desktop keyring. Every device is identified by its live `ro.serialno`,
# never by its adb serial: wireless addresses change and can be reused by
# another device, which must never receive this device's PIN.
#
#   status SERIAL            → "keep=on|off running=1|0 secret=none|saved|blocked"
#   keep-awake on|off SERIAL   remember the choice and start/stop the keeper
#   connected WAKE UNLOCK SERIAL...   restart wanted keepers, then wake/unlock (0|1)
#   wake SERIAL | unlock SERIAL
#   secret-set SERIAL (secret on stdin) | secret-clear SERIAL
#
# Exit codes: 0 done, 1 adb or usage error, 3 no secret saved, 4 unlock paused
# after a failed try, 5 keyring unavailable.
set -uo pipefail
export LC_ALL=C

source "$(dirname -- "${BASH_SOURCE[0]}")/proc-lib.sh"
keeper_dir="$runtime_dir/keepers"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/droidlink/devices"
mkdir -p -m 700 -- "$keeper_dir" "$state_root"

die() {
  local code="$1"
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

valid_serial() {
  [[ "$1" =~ ^[A-Za-z0-9._:@-]{1,128}$ ]] || die 1 "Unexpected adb serial '$1'; expected letters, digits and . _ : @ -."
}

device_shell() {
  timeout "${2:-4}" adb -s "$1" shell "${@:3}" 2>/dev/null | tr -d '\r'
}

# The hardware serial reported by the device right now.
device_id() {
  local id
  id="$(device_shell "$1" 4 getprop ro.serialno)" || die 1 "Couldn't reach $1 over adb."
  [[ "$id" =~ ^[A-Za-z0-9._-]{4,64}$ ]] || die 1 "$1 reported hardware serial '$id'; expected 4-64 letters, digits, . _ -."
  printf '%s' "$id"
}

# Prints "awake|dozing|asleep locked|unlocked".
power_state() {
  local reply wake lock
  reply="$(device_shell "$1" 4 'dumpsys power 2>/dev/null | grep -m1 "mWakefulness="; dumpsys window 2>/dev/null | grep -m1 "isKeyguardShowing="')" || return 1
  [[ "$reply" =~ mWakefulness=([A-Za-z]+) ]] || return 1
  wake="${BASH_REMATCH[1],,}"
  [[ "$reply" =~ isKeyguardShowing=(true|false) ]] || return 1
  [[ "${BASH_REMATCH[1]}" == true ]] && lock=locked || lock=unlocked
  printf '%s %s\n' "$wake" "$lock"
}

wake_device() {
  device_shell "$1" 4 input keyevent KEYCODE_WAKEUP >/dev/null || die 1 "Couldn't wake $1 over adb."
}

# --- Keep awake --------------------------------------------------------------

keeper_running() {
  local pid started
  [[ -f "$keeper_dir/$1" ]] || return 1
  read -r pid started _ <"$keeper_dir/$1" || return 1
  [[ "$pid" =~ ^[0-9]+$ && "$(start_time "$pid" 2>/dev/null)" == "$started" ]]
}

# scrcpy without video doesn't power the screen on, and --keep-active only
# extends an awake screen, so the keeper wakes first. scrcpy restores the
# device when it exits, and exits by itself when the device disconnects.
start_keeper() {
  local serial="$1" id="$2" pid
  keeper_running "$id" && return 0
  wake_device "$serial"
  setsid scrcpy "--serial=$serial" --no-video --no-audio --no-window --keep-active </dev/null >"$keeper_dir/$id.log" 2>&1 8>&- &
  pid=$!
  printf '%s %s %s\n' "$pid" "$(start_time "$pid")" "$serial" >"$keeper_dir/$id"
}

stop_keeper() {
  local pid
  keeper_running "$1" && read -r pid _ <"$keeper_dir/$1" && kill -TERM "$pid" 2>/dev/null
  rm -f -- "$keeper_dir/$1"
}

# --- Unlock ------------------------------------------------------------------

# Printable ASCII only: `input text` can't type anything else, and a value it
# can't type must be refused here rather than cost the single attempt.
valid_secret() {
  [[ ${#1} -ge 4 && ${#1} -le 64 && "$1" =~ ^[\ -~]+$ && "$1" != ' '* && "$1" != *' ' ]]
}

# One `input text` per word, joined by SPACE key presses: `input text` drops
# spaces and turns "%s" into one, so words are also cut after each "%".
# Words are single-quoted for the device shell.
typing_script() {
  local word piece first=1
  local -a words pieces
  IFS=$'\x1f' read -r -a words <<<"${1// /$'\x1f'}"
  for word in "${words[@]}"; do
    ((first)) || echo 'input keyevent KEYCODE_SPACE'
    first=0
    IFS=$'\x1e' read -r -a pieces <<<"${word//%/%$'\x1e'}"
    for piece in "${pieces[@]}"; do
      [[ -n "$piece" ]] && printf "input text '%s'\n" "${piece//\'/\'\\\'\'}"
    done
  done
}

# Ask the keyguard for its bouncer, then confirm a PIN or password field is
# on screen (AOSP and One UI ids) before anything is typed: keys sent to a
# pattern lock or a missing bouncer would land elsewhere.
show_bouncer() {
  local ui
  ui="$(device_shell "$1" 8 'input keyevent KEYCODE_WAKEUP; sleep 0.3; wm dismiss-keyguard; sleep 0.8; uiautomator dump /data/local/tmp/droidlink-ui.xml >/dev/null 2>&1; cat /data/local/tmp/droidlink-ui.xml 2>/dev/null; rm -f /data/local/tmp/droidlink-ui.xml')"
  [[ "$ui" != *'id/lockPatternView"'* ]] || die 1 "This device uses a pattern lock, which DroidLink can't enter. Nothing was typed."
  [[ "$ui" == *'id/passwordEntry"'* || "$ui" == *'id/pinEntry"'* ]] || die 1 "The PIN or password field didn't appear on $1. Nothing was typed."
}

# Sent on stdin so the secret never appears in a host process's arguments.
send_secret() {
  {
    typing_script "$2"
    echo 'input keyevent KEYCODE_ENTER'
    echo 'exit'
  } | timeout 10 adb -s "$1" shell >/dev/null 2>&1
}

still_locked() {
  local attempt state
  for ((attempt = 0; attempt < 8; attempt++)); do
    sleep 0.5
    state="$(power_state "$1")" || continue
    [[ "$state" == *' unlocked' ]] && return 1
  done
  return 0
}

unlock_device() {
  local serial="$1" id state secret dir
  id="$(device_id "$serial")"
  dir="$state_root/$id"
  [[ ! -e "$dir/blocked" ]] || die 4 "Unlock is paused after a failed try. Unlock the device by hand, then save its PIN again."
  [[ -e "$dir/secret" ]] || die 3 "No unlock PIN saved for this device."
  secret="$(secret-tool lookup app droidlink device "$id" 2>/dev/null)" || { rm -f -- "$dir/secret"; die 3 "The keyring has no unlock PIN for this device. Save it again."; }
  wake_device "$serial"
  state="$(power_state "$serial")" || die 1 "Couldn't read the lock state of $serial."
  [[ "$state" == *' locked' ]] || { echo 'Device is awake and unlocked.'; return 0; }
  show_bouncer "$serial"
  # Written before typing so a crash mid-attempt can't lead to a second try.
  touch -- "$dir/blocked"
  send_secret "$serial" "$secret" || die 4 "adb stopped while entering the PIN. Unlock is paused; save the PIN again."
  still_locked "$serial" && die 4 "The lock screen is still showing. Unlock is paused so a wrong PIN isn't retried; save it again."
  rm -f -- "$dir/blocked"
  echo 'Device unlocked.'
}

save_secret() {
  local serial="$1" id secret dir
  secret="$(cat)"
  secret="${secret%$'\n'}"
  valid_secret "$secret" || die 1 "Use 4-64 plain ASCII characters (letters, digits, symbols, inner spaces); accents and emoji can't be typed over adb."
  command -v secret-tool >/dev/null 2>&1 || die 5 "secret-tool (libsecret) isn't installed; the PIN is never stored in plain text."
  id="$(device_id "$serial")"
  dir="$state_root/$id"
  mkdir -p -m 700 -- "$dir"
  printf '%s' "$secret" | secret-tool store --label="DroidLink unlock for $id" app droidlink device "$id" 2>/dev/null ||
    die 5 "The desktop keyring refused the PIN. Is a keyring (gnome-keyring, KWallet) running and unlocked?"
  touch -- "$dir/secret"
  rm -f -- "$dir/blocked"
  echo 'Unlock PIN saved in the keyring.'
}

clear_secret() {
  local id
  id="$(device_id "$1")"
  secret-tool clear app droidlink device "$id" 2>/dev/null
  rm -f -- "$state_root/$id/secret" "$state_root/$id/blocked"
  echo 'Unlock PIN removed.'
}

# --- Commands ----------------------------------------------------------------

print_status() {
  local id dir keep=off running=0 secret=none
  id="$(device_id "$1")"
  dir="$state_root/$id"
  [[ -e "$dir/keep-awake" ]] && keep=on
  keeper_running "$id" && running=1
  [[ -e "$dir/secret" ]] && secret=saved
  [[ -e "$dir/blocked" ]] && secret=blocked
  printf 'keep=%s running=%s secret=%s\n' "$keep" "$running" "$secret"
}

set_keep_awake() {
  local id
  [[ "$1" == on || "$1" == off ]] || die 1 "keep-awake takes on|off, got '$1'."
  id="$(device_id "$2")"
  mkdir -p -m 700 -- "$state_root/$id"
  if [[ "$1" == on ]]; then
    touch -- "$state_root/$id/keep-awake"
    start_keeper "$2" "$id"
    echo 'Keeping the screen on.'
  else
    rm -f -- "$state_root/$id/keep-awake"
    stop_keeper "$id"
    echo 'Screen timeout restored.'
  fi
}

# Unlocking a device without a saved PIN falls back to waking it.
on_connect() {
  local serial="$1" wake="$2" unlock="$3" id
  id="$(device_id "$serial")"
  [[ -e "$state_root/$id/keep-awake" ]] && start_keeper "$serial" "$id"
  if [[ "$unlock" == 1 && -e "$state_root/$id/secret" ]]; then
    unlock_device "$serial"
  elif [[ "$wake" == 1 || "$unlock" == 1 ]]; then
    wake_device "$serial"
  fi
  return 0
}

# Several popups or monitors may ask at once; one keeper per device.
exec 8>"$runtime_dir/power.lock"
flock -x 8
command="${1:-}"
shift || true
case "$command" in
  status)
    valid_serial "${1:-}"
    print_status "$1"
    ;;
  keep-awake)
    valid_serial "${2:-}"
    set_keep_awake "${1:-}" "$2"
    ;;
  connected)
    [[ "${1:-}" =~ ^[01]$ && "${2:-}" =~ ^[01]$ ]] || die 1 "connected takes WAKE UNLOCK (0|1) then serials."
    wake="$1" unlock="$2"
    shift 2
    # Runs on every connect; skip adb entirely when nothing was asked for.
    [[ "$wake$unlock" != 00 ]] || compgen -G "$state_root/*/keep-awake" >/dev/null || exit 0
    status=0
    for serial in "$@"; do
      valid_serial "$serial"
      (on_connect "$serial" "$wake" "$unlock") || status=$?
    done
    exit "$status"
    ;;
  wake)
    valid_serial "${1:-}"
    wake_device "$1"
    echo 'Device woken.'
    ;;
  unlock)
    valid_serial "${1:-}"
    unlock_device "$1"
    ;;
  secret-set)
    valid_serial "${1:-}"
    save_secret "$1"
    ;;
  secret-clear)
    valid_serial "${1:-}"
    clear_secret "$1"
    ;;
  *)
    die 1 "Usage: device-power.sh status|keep-awake|connected|wake|unlock|secret-set|secret-clear …; got '$command'."
    ;;
esac
