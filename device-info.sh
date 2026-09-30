#!/usr/bin/env bash
# Print "serial<TAB>key<TAB>value" lines describing each given ready device:
# battery, Android version, memory, screen size and storage. One adb shell per
# device, queried in parallel, each bounded by a timeout. Raw dumps stay here:
# Samsung appends a battery history to `dumpsys battery`, and only the indented
# header lines of the current state are read.
set -uo pipefail
remote='echo @battery; dumpsys battery; echo @version; getprop ro.build.version.release; getprop ro.build.version.sdk; echo @mem; grep MemTotal /proc/meminfo; echo @size; wm size; echo @volumes; sm list-volumes all 2>/dev/null; echo @df; df -k /data /storage/* 2>/dev/null'
for serial in "$@"; do
  (
    info="$(timeout 4 adb -s "$serial" shell "$remote" 2>/dev/null | tr -d '\r' | awk -v serial="$serial" '
      function out(key, value) { if (value != "" && !(key in seen)) { seen[key] = 1; printf "%s\t%s\t%s\n", serial, key, value } }
      /^@[a-z]+$/ { section = substr($0, 2); line = 0; next }
      { line++ }
      section == "battery" && /^  level: [0-9]+$/ { out("battery_level", $2) }
      section == "battery" && /^  status: [0-9]+$/ { out("battery_status", $2) }
      section == "battery" && /^  temperature: -?[0-9]+$/ { out("battery_temp", $2) }
      section == "battery" && /^  (AC|USB|Wireless) powered: true$/ { plugged = plugged (plugged == "" ? "" : ",") tolower($1) }
      section == "version" && line == 1 { out("android", $0) }
      section == "version" && line == 2 && /^[0-9]+$/ { out("sdk", $0) }
      section == "mem" && $1 == "MemTotal:" { out("mem_kb", $2) }
      section == "size" && /^Physical size: [0-9]+x[0-9]+$/ { out("screen", $3) }
      # "public:179,1 mounted 7934-B54D": block major 179 is an SD card, 8 a USB drive.
      section == "volumes" && /^public:[0-9]+,[0-9]+ mounted / { split(substr($1, 8), dev, ","); kind[$3] = dev[1] == 179 ? "sd" : dev[1] == 8 ? "usb" : "external" }
      section == "df" && NF >= 6 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
        mount = $NF
        if (mount ~ /^\/data(\/|$)/) out("internal", $3 ":" $2)
        else if (mount ~ /^\/storage\/[^\/]+$/ && mount !~ /^\/storage\/(emulated|self|sdcard[0-9]*)$/) {
          id = substr(mount, 10)
          out("external_" id, id ":" (id in kind ? kind[id] : "external") ":" $3 ":" $2)
        }
      }
      END { out("battery_plugged", plugged) }
    ')"
    # One write per device so parallel results never interleave.
    [[ -n "$info" ]] && printf '%s\n' "$info"
  ) &
done
wait
exit 0
