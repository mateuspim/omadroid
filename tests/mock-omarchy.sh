#!/usr/bin/env bash
set -eu
# hotkey.sh reads the bound keys; this list mirrors Omarchy's format.
if [[ "$*" == 'menu keybindings --print' ]]; then
  printf '%s\n' 'SUPER + K                           → Keybindings' \
    'SUPER CTRL + A                      → Audio' \
    'SUPER SHIFT ALT + B                 → Browser' \
    'CTRL ALT + DELETE                   → Something'
  [[ -z "${OMADROID_HYPR_BINDINGS:-}" ]] || sed -n 's/^o\.bind("\([^"]*\)", "\([^"]*\)".*/\1   → \2/p' "$OMADROID_HYPR_BINDINGS" 2>/dev/null
  exit 0
fi
[[ "${1:-}" == launch && "${2:-}" == terminal ]] || exit 2
shift 2
[[ "${1:-}" == --app-id=io.github.mateuspim.omadroid && "${2:-}" == --hold && "${3:-}" == --title=OmaDroid ]] || exit 2
shift 3
[[ "${1:-}" == -- ]] || exit 2
shift
# Ghostty's hold mode drops empty arguments; mimic it so launches must not
# depend on them reaching the command.
args=()
for arg in "$@"; do
  [[ "$arg" ]] && args+=("$arg")
done
exec "${args[@]}"
