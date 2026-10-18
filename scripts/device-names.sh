#!/usr/bin/env bash
# Print "serial<TAB>name" for each given ready device whose Android device
# name (Settings › About › Device name) is set. adb devices -l only reports
# the model code. Devices are queried in parallel, each bounded by a timeout.
set -uo pipefail
for serial in "$@"; do
  (
    name="$(timeout 4 adb -s "$serial" shell settings get global device_name 2>/dev/null | head -n 1)"
    name="${name//[[:cntrl:]]/}"
    [[ -n "$name" && "$name" != null ]] && printf '%s\t%s\n' "$serial" "${name:0:64}"
  ) &
done
wait
exit 0
