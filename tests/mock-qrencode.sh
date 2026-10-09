#!/usr/bin/env bash
# Records the payload read on stdin and the argv in DROIDLINK_QR_LOG, then
# draws a fixed 3×3 code the way `qrencode -t ASCII` does (two characters per module).
set -eu
[[ -z "${DROIDLINK_QR_LOG:-}" ]] || { printf 'argv %s\n' "$*"; printf 'payload %s\n' "$(cat)"; } >>"$DROIDLINK_QR_LOG"
printf '%s\n' '######' '##  ##' '  ####'
