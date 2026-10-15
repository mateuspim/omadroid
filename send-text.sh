#!/usr/bin/env bash
# Type text and press keys on a device with `adb shell input`, for the Send
# text overlay.
#
#   send-text.sh SERIAL STEP... → nothing on success
#   STEP is text:TEXT or key:NAME, e.g. key:ctrl+a key:backspace text:hello key:enter
#
# Every step is checked before anything is sent, then all of them run in one
# `adb shell`, chained with && so a failing step stops the rest. adb joins its
# argv into one string for the device's sh, so text is sent as one
# single-quoted word; spaces become %s, which `input text` types as a space. A
# literal "%s" in the text is typed as a space too: `input text` can't escape it.
#
# Key names: a letter, digit or f1–f12, or one of the names in key_codes below,
# optionally after ctrl+, shift+, alt+ or meta+ (ctrl-a works too; sent with `input
# keycombination`, Android 13+).
#
# Exit codes: 0 sent, 1 adb or usage error, 2 a step can't be sent.
set -uo pipefail
export LC_ALL=C

source "$(dirname -- "${BASH_SOURCE[0]}")/adb-lib.sh"

declare -A key_codes=(
  [enter]=ENTER [tab]=TAB [space]=SPACE [backspace]=DEL [del]=FORWARD_DEL [delete]=FORWARD_DEL
  [esc]=ESCAPE [escape]=ESCAPE [home]=MOVE_HOME [end]=MOVE_END [up]=DPAD_UP [down]=DPAD_DOWN
  [left]=DPAD_LEFT [right]=DPAD_RIGHT [pageup]=PAGE_UP [pagedown]=PAGE_DOWN [insert]=INSERT
  [back]=BACK [menu]=MENU [search]=SEARCH
)
declare -A modifier_codes=([ctrl]=CTRL_LEFT [shift]=SHIFT_LEFT [alt]=ALT_LEFT [meta]=META_LEFT)
known_keys="a-z, 0-9, f1-f12, ${!key_codes[*]}"

# printable ASCII only, as SendText.unsupportedChars checks in the overlay.
text_command() {
  [[ -n "$1" ]] || die 2 "Empty text step; expected text:SOMETHING."
  [[ "$1" =~ ^[\ -~]+$ ]] || die 2 "Can't type '$1': only printable ASCII text is supported."
  local text="${1// /%s}" escaped="'\\''"
  printf "input text '%s'" "${text//\'/$escaped}"
}

# "a" → KEYCODE_A, "f5" → KEYCODE_F5, "enter" → KEYCODE_ENTER.
key_code() {
  [[ "$1" =~ ^[a-z0-9]$ ]] && { printf 'KEYCODE_%s' "${1^^}"; return 0; }
  [[ "$1" =~ ^f([1-9]|1[0-2])$ ]] && { printf 'KEYCODE_%s' "${1^^}"; return 0; }
  [[ -n "${key_codes[$1]:-}" ]] && { printf 'KEYCODE_%s' "${key_codes[$1]}"; return 0; }
  return 1
}

# "ctrl+shift+z" → "input keycombination KEYCODE_CTRL_LEFT KEYCODE_SHIFT_LEFT KEYCODE_Z".
key_command() {
  local name="$1" parts codes=() part code
  IFS=+- read -ra parts <<<"$name"
  [[ ${#parts[@]} -gt 0 && "$name" != *[+-] ]] || die 2 "Unknown key '{$name}'; expected one of $known_keys, optionally after ctrl+, shift+, alt+ or meta+."
  for part in "${parts[@]:0:${#parts[@]}-1}"; do
    [[ -n "${modifier_codes[$part]:-}" ]] || die 2 "Unknown modifier '$part' in '{$name}'; expected ctrl, shift, alt or meta."
    codes+=("KEYCODE_${modifier_codes[$part]}")
  done
  code="$(key_code "${parts[-1]}")" || die 2 "Unknown key '{$name}'; expected one of $known_keys, optionally after ctrl+, shift+, alt+ or meta+."
  ((${#codes[@]})) && printf 'input keycombination %s %s' "${codes[*]}" "$code" || printf 'input keyevent %s' "$code"
}

step_command() {
  case "$1" in
    text:*) text_command "${1#text:}" ;;
    key:*) key_command "${1#key:}" ;;
    *) die 1 "Unexpected step '$1'; expected text:TEXT or key:NAME." ;;
  esac
}

# Runs the chained commands and dies with adb's own message.
device_input() {
  local serial="$1" reply
  reply="$(timeout 20 adb -s "$serial" shell "$2" 2>&1)" ||
    die 1 "Couldn't type on $serial: ${reply:-no answer from adb}"
  # `adb shell` exits 0 on some devices even when input throws.
  [[ "$reply" =~ Exception|Error: ]] && die 1 "Couldn't type on $serial: $reply"
  return 0
}

serial="${1:-}"
valid_serial "$serial"
shift
(($#)) || die 1 "Nothing to send; expected steps like text:hello or key:enter."
script=""
for step in "$@"; do
  command="$(step_command "$step")" || exit $?
  script+="${script:+ && }$command"
done
device_input "$serial" "$script"
