#!/usr/bin/env bash
# Keep the Send text overlay's key binding in Hyprland's bindings.lua, so a new
# setup gets it from DroidLink's Settings page instead of a hand edit. Omarchy
# gives plugins no way to bind keys, so DroidLink owns one marked block at the
# end of the file and never touches anything outside it.
#
#   hotkey.sh status     → "installed SUPER + ALT + D" or "none"
#   hotkey.sh set COMBO  → "installed COMBO" (replaces DroidLink's own bind)
#   hotkey.sh remove     → "none"
#
# Exit codes: 0 done, 1 usage or file error, 2 the combination is already bound.
set -uo pipefail
export LC_ALL=C

source "$(dirname -- "${BASH_SOURCE[0]}")/adb-lib.sh"
bindings="${DROIDLINK_HYPR_BINDINGS:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua}"
description="DroidLink send text"
block_start="-- >>> DroidLink send text (managed by DroidLink; change it on its Settings page)"
block_end="-- <<< DroidLink send text"
modifiers=(SUPER CTRL ALT SHIFT)

# "super+alt + d" → "SUPER + ALT + D": known modifiers in a fixed order, then one key.
normalize_combo() {
  local token key="" found=() mod tokens
  read -ra tokens <<<"$(tr '[:lower:]+' '[:upper:] ' <<<"$1")"
  for token in "${tokens[@]}"; do
    [[ " ${modifiers[*]} " == *" $token "* ]] && { found+=("$token"); continue; }
    [[ -z "$key" && "$token" =~ ^[A-Z0-9]+$ ]] || die 1 "Unexpected key combination '$1'; expected modifiers and one key, like SUPER + ALT + D."
    key="$token"
  done
  [[ -n "$key" && ${#found[@]} -gt 0 ]] || die 1 "Unexpected key combination '$1'; expected at least one of ${modifiers[*]} and one key, like SUPER + ALT + D."
  for mod in "${modifiers[@]}"; do
    [[ " ${found[*]} " == *" $mod "* ]] && printf '%s + ' "$mod"
  done
  printf '%s' "$key"
}

# The description of another binding on COMBO, from Omarchy's list, which
# writes "SUPER SHIFT ALT + B   → Name" with its own modifier order.
taken_by() {
  local wanted
  wanted="$(combo_set "$1")"
  omarchy menu keybindings --print 2>/dev/null | while IFS= read -r line; do
    [[ "$line" == *"→"* ]] || continue
    local keys="${line%%→*}" name="${line#*→ }"
    [[ "$name" == "$description" ]] && continue
    [[ "$(combo_set "$keys")" == "$wanted" ]] && { printf '%s' "$name"; return; }
  done
}

# Order-free form of a combination for comparing: sorted upper-case tokens.
combo_set() {
  tr '[:lower:]+' '[:upper:] ' <<<"$1" | tr -s ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '
}

current_combo() {
  [[ -f "$bindings" ]] || return 0
  awk -v start="$block_start" -v end="$block_end" '
    $0 == start { inside = 1; next }
    $0 == end { inside = 0 }
    inside && match($0, /^o\.bind\("[^"]+"/) { print substr($0, 9, RLENGTH - 9); exit }
  ' "$bindings"
}

# The file without DroidLink's block, then the block for COMBO ("" for none).
# Written in place so a bindings.lua symlinked from dotfiles stays a symlink.
write_bindings() {
  local combo="$1" next
  next="$(mktemp)"
  [[ -f "$bindings" ]] && awk -v start="$block_start" -v end="$block_end" '
    $0 == start { inside = 1; next }
    inside && $0 == end { inside = 0; next }
    !inside
  ' "$bindings" >"$next"
  [[ -n "$combo" ]] && printf '%s\no.bind("%s", "%s", "omarchy-shell shell toggle pym.droidlink")\n%s\n' \
    "$block_start" "$combo" "$description" "$block_end" >>"$next"
  if [[ -f "$bindings" ]] && cmp -s "$next" "$bindings"; then
    rm -f -- "$next"
    return 0
  fi
  [[ -f "$bindings" ]] && cp -- "$bindings" "$bindings.bak.$(date +%s)"
  cat -- "$next" >"$bindings" || { rm -f -- "$next"; die 1 "Couldn't write $bindings."; }
  rm -f -- "$next"
  # Hyprland reloads on its own when autoreload is on; this covers it being off.
  hyprctl reload >/dev/null 2>&1 || true
}

print_status() {
  local combo
  combo="$(current_combo)"
  [[ -n "$combo" ]] && printf 'installed %s\n' "$combo" || printf 'none\n'
}

case "${1:-}" in
  status) print_status ;;
  set)
    combo="$(normalize_combo "${2:-}")" || exit $?
    owner="$(taken_by "$combo")"
    [[ -z "$owner" ]] || die 2 "$combo is already bound to $owner. Pick another combination."
    [[ -d "$(dirname -- "$bindings")" ]] || die 1 "Hyprland's config folder $(dirname -- "$bindings") doesn't exist."
    write_bindings "$combo"
    print_status
    ;;
  remove)
    [[ -f "$bindings" ]] && write_bindings ""
    print_status
    ;;
  *) die 1 "Unexpected command '${1:-}'; expected status, set COMBO or remove." ;;
esac
