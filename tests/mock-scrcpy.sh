#!/usr/bin/env bash
set -eu
for arg in "$@"; do
  if [[ "$arg" == --video-codec=av1 ]]; then
    printf '%s\n' 'ERROR: AV1 encoder unavailable (fixture)' >&2
    exit 1
  fi
done
[[ "$1" == --serial=USB123 ]] || exit 5
printf '%s\n' "$@" > "$DROIDLINK_TEST_ARGS"
printf '%s\n' 'INFO: scrcpy fixture started'
for arg in "$@"; do
  if [[ "$arg" == --max-fps=120 ]]; then
    trap 'exit 0' TERM
    while true; do sleep 0.1; done
  fi
done
