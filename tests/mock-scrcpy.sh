#!/usr/bin/env bash
set -eu
for arg in "$@"; do
  if [[ "$arg" == --video-codec=av1 ]]; then
    printf '%s\n' 'ERROR: AV1 encoder unavailable (fixture)' >&2
    exit 1
  fi
done
[[ "$1" == --serial=USB123 ]] || exit 5
# The real camera list of a Galaxy Tab S11, captured from scrcpy 4.1.
if [[ "${2:-}" == --list-camera-sizes ]]; then
  cat "${DROIDLINK_TEST_CAMERAS:?}"
  exit 0
fi
# device-power.sh's keeper runs until stopped, like the real one.
if [[ " $* " == *' --no-window --keep-active '* ]]; then
  trap 'exit 0' TERM
  while true; do sleep 0.1; done
fi
printf '%s\n' "$@" >> "$DROIDLINK_TEST_ARGS"
printf '%s\n' 'INFO: scrcpy fixture started'
for arg in "$@"; do
  if [[ "$arg" == --video-source=camera ]]; then
    trap 'exit 0' TERM
    while true; do sleep 0.1; done
  fi
  if [[ "$arg" == --max-fps=120 ]]; then
    # DROIDLINK_SCRCPY_IGNORE_TERM models a scrcpy that hangs on shutdown.
    if [[ -n "${DROIDLINK_SCRCPY_IGNORE_TERM:-}" ]]; then trap '' TERM; else trap 'exit 0' TERM; fi
    while true; do sleep 0.1; done
  fi
done
