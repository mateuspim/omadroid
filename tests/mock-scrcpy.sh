#!/usr/bin/env bash
set -eu
for arg in "$@"; do
  if [[ "$arg" == --video-codec=av1 ]]; then
    printf '%s\n' 'ERROR: AV1 encoder unavailable (fixture)' >&2
    exit 1
  fi
done
[[ "$1" == --serial=USB123 ]] || exit 5
# App names for device-volume.sh, in scrcpy 4.1's format (system apps "*").
if [[ "${2:-}" == --list-apps ]]; then
  printf '%s\n' ' * Videos                         com.example.videos' ' - Starship: Demo Game              com.example.starship'
  exit 0
fi
# The real camera list of a Galaxy Tab S11, captured from scrcpy 4.1.
if [[ "${2:-}" == --list-camera-sizes ]]; then
  cat "${OMADROID_TEST_CAMERAS:?}"
  exit 0
fi
# device-power.sh's keeper runs until stopped, like the real one.
if [[ " $* " == *' --no-window --keep-active '* ]]; then
  trap 'exit 0' TERM
  while true; do sleep 0.1; done
fi
printf '%s\n' "$@" >> "$OMADROID_TEST_ARGS"
printf '%s\n' 'INFO: scrcpy fixture started'
# OMADROID_SCRCPY_STAY=1 keeps every session running until stopped, and
# takes two seconds to stop, so a preview can show a mirror (or audio) being
# replaced by a switch.
if [[ -n "${OMADROID_SCRCPY_STAY:-}" ]]; then
  trap 'sleep 2; exit 0' TERM
  while true; do sleep 0.1; done
fi
for arg in "$@"; do
  if [[ "$arg" == --video-source=camera ]]; then
    trap 'exit 0' TERM
    while true; do sleep 0.1; done
  fi
  if [[ "$arg" == --max-fps=120 ]]; then
    # OMADROID_SCRCPY_IGNORE_TERM models a scrcpy that hangs on shutdown.
    if [[ -n "${OMADROID_SCRCPY_IGNORE_TERM:-}" ]]; then trap '' TERM; else trap 'exit 0' TERM; fi
    while true; do sleep 0.1; done
  fi
done
