#!/usr/bin/env bash
# Enumerate actual v4l2loopback nodes; custom card labels are allowed.
set -euo pipefail
sys_root="${DROIDLINK_VIDEO_SYSFS:-/sys/class/video4linux}"
dev_root="${DROIDLINK_VIDEO_DEV:-/dev}"
module_root="${DROIDLINK_VIDEO_MODULE_SYSFS:-/sys/module/v4l2loopback}"

# Most specific first: a module loaded or installed from any package (a -git
# build, a prebuilt kernel module) must not be reported as a missing package.
missing_output_reason() {
  if [[ -d "$module_root" ]]; then
    echo no-output >&2
  elif modinfo -n v4l2loopback >/dev/null 2>&1; then
    echo module-not-loaded >&2
  elif pacman -Qq v4l2loopback-dkms >/dev/null 2>&1; then
    echo module-unavailable >&2
  else
    echo missing-package >&2
  fi
}

is_loopback() {
  local node="$1" target
  [[ "$node" =~ ^video[0-9]+$ && -e "$dev_root/$node" ]] || return 1
  target="$(readlink -f -- "$sys_root/$node" 2>/dev/null)" || return 1
  [[ "$target" == */devices/virtual/video4linux/"$node" ]] || return 1
  # keep_format went away in v4l2loopback 0.15; max_openers is in every release.
  [[ -e "$sys_root/$node/max_openers" || -e "$sys_root/$node/keep_format" ]]
}

case "${1:-}" in
  list)
    found=0
    for path in "$sys_root"/video*; do
      node="${path##*/}"
      is_loopback "$node" || continue
      found=1
      label="$(cat -- "$path/name" 2>/dev/null || true)"
      printf '/dev/%s\t%s\n' "$node" "${label//$'\t'/ }"
    done
    (( found )) || missing_output_reason
    ;;
  check)
    sink="${2:-}"
    [[ "$sink" =~ ^/dev/video[0-9]+$ ]] || { echo "Invalid webcam output '$sink'; select a listed v4l2loopback device." >&2; exit 2; }
    node="${sink##*/}"
    is_loopback "$node" || { echo "No v4l2loopback output at $sink. Create a loopback device and refresh the list." >&2; exit 1; }
    [[ -w "$dev_root/$node" ]] || { echo "Cannot write to $sink. Check its video group permissions." >&2; exit 1; }
    # An Apply restart sets DROIDLINK_KEEP_READERS: a call reading the output
    # bridges the gap. If the new size clashes, scrcpy fails with "busy" and
    # session.sh reports the output as occupied.
    if [[ "${DROIDLINK_KEEP_READERS:-}" != 1 ]] && command -v fuser >/dev/null 2>&1 && fuser "$dev_root/$node" >/dev/null 2>&1; then
      echo "$sink is occupied. Close OBS, your video call, or the app using it, then retry." >&2
      exit 1
    fi
    ;;
  cameras)
    # Asks the phone for its cameras, sizes and frame rates; Model.js parses
    # the list. Needs no session, and leaves a running one alone.
    serial="${2:-}"
    [[ "$serial" && "$serial" != -* && "$serial" != *[[:space:][:cntrl:]]* ]] || { echo "Invalid device '$serial'." >&2; exit 2; }
    exec scrcpy --serial="$serial" --list-camera-sizes
    ;;
  *) echo 'Usage: webcam-devices.sh list|check /dev/videoN|cameras SERIAL' >&2; exit 2 ;;
esac
