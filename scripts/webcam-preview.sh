#!/usr/bin/env bash
# Feeds the in-panel webcam preview: ffmpeg reads the loopback like any video
# app and keeps one small JPEG updated. ffmpeg asks the driver for its current
# format, unlike Qt's camera, whose cached format list could push a stale size
# onto the shared output and garble it for every app.
set -euo pipefail
sys_root="${OMADROID_VIDEO_SYSFS:-/sys/class/video4linux}"
source "$(dirname -- "${BASH_SOURCE[0]}")/proc-lib.sh"
device="${1:-}" out="${2:-}"
[[ "$device" =~ ^/dev/video[0-9]+$ ]] || { echo "Invalid preview device '$device'." >&2; exit 2; }
[[ "$out" =~ ^"$runtime_dir"/preview-[A-Za-z0-9]+\.jpg$ ]] || { echo "Invalid preview path '$out'." >&2; exit 2; }
for program in ffmpeg ffprobe setpriv; do
  command -v "$program" >/dev/null 2>&1 || { echo "The preview needs $program (ffmpeg, util-linux)." >&2; exit 127; }
done

# scrcpy's size, from the driver ("YU12:1080x1920@30"), against what readers
# receive. They differ when a reader fixed an older size; every app then sees
# garbled video until all of them close.
node="${device##*/}"
format="$(cat -- "$sys_root/$node/format" 2>/dev/null || true)"
writing="${format#*:}"
writing="${writing%@*}"
reading="$(timeout 5 ffprobe -v error -f v4l2 -show_entries stream=width,height -of csv=p=0:s=x "$device" 2>/dev/null || true)"
if [[ "$writing" =~ ^[0-9]+x[0-9]+$ && "$reading" && "$reading" != "$writing" ]]; then
  echo "Apps reading $device get $reading while scrcpy writes $writing, so video is garbled. Close every app using $device, then stop and start the webcam." >&2
  exit 3
fi

# Frames of previews that ended (each widget names its own); a running
# preview rewrites its file 12 times a second.
find "$runtime_dir" -maxdepth 1 -name 'preview-*.jpg*' -mmin +1 -delete 2>/dev/null || true

# exec: Quickshell stops the preview by signalling this exact process.
# pdeathsig: ffmpeg also ends if the shell dies, so it never keeps holding the
# output and blocking the next webcam.
exec setpriv --pdeathsig TERM ffmpeg -hide_banner -loglevel error -nostdin \
  -f v4l2 -i "$device" -vf "fps=12,scale=480:-2" -q:v 7 \
  -f image2 -update 1 -atomic_writing 1 -y "$out"
