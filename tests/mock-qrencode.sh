#!/usr/bin/env bash
# Records the payload read on stdin and the argv in OMADROID_QR_LOG, then
# draws a fixed 3×3 code the way `qrencode -t ASCII` does (two characters per module).
set -eu
[[ -z "${OMADROID_QR_LOG:-}" ]] || { printf 'argv %s\n' "$*"; printf 'payload %s\n' "$(cat)"; } >>"$OMADROID_QR_LOG"
printf '%s\n' '######' '##  ##' '  ####'
