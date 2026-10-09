#!/usr/bin/env bash
# Move a USB-connected device to wireless ADB, so its cable can be unplugged.
# Android 11+ turns on Wireless debugging (TLS) and connects to the port adbd
# publishes in service.adb.tls.port; a host already trusted over USB is usually
# accepted without pairing. Older Android falls back to `adb tcpip 5555`, which
# is unencrypted and lasts until the device reboots.
#
#   go-wireless.sh SERIAL → "Connected to HOST:PORT. …" on stdout
#
# Exit codes: 0 connected, 1 adb or usage error, 2 not on Wi-Fi, 3 Wireless
# debugging didn't start, 4 the connection was refused or not authorized.
set -uo pipefail
export LC_ALL=C

source "$(dirname -- "${BASH_SOURCE[0]}")/adb-lib.sh"
# Seconds between polls; tests shorten it.
poll_delay="${DROIDLINK_POLL_DELAY:-0.5}"
tls_hint="If this computer isn't paired for Wireless debugging yet, use Pair with QR code in Wireless."

# The device's IPv4 address on Wi-Fi, from "47: wlan0    inet 192.168.1.42/24 …".
wifi_address() {
  local address
  address="$(device_shell "$1" 4 ip -4 -o addr show | awk '$2 ~ /^wlan/ && $3 == "inet" { sub(/\/.*/, "", $4); print $4; exit }')"
  [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  printf '%s' "$address"
}

tls_port() {
  local port
  port="$(device_shell "$1" 4 getprop service.adb.tls.port)"
  [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && printf '%s' "$port"
}

# Turns Wireless debugging on and prints its port. A port left over from an
# earlier session can linger in the property, so a fresh start waits for a new one.
start_tls() {
  local serial="$1" stale="" port
  if [[ "$(device_shell "$serial" 4 settings get global adb_wifi_enabled)" != 1 ]]; then
    stale="$(tls_port "$serial")"
    device_shell "$serial" 4 settings put global adb_wifi_enabled 1 >/dev/null ||
      die 1 "Couldn't turn on Wireless debugging on $serial."
  fi
  for _ in {1..20}; do
    port="$(tls_port "$serial")"
    [[ -n "$port" && "$port" != "$stale" ]] && { printf '%s' "$port"; return 0; }
    sleep "$poll_delay"
  done
  die 3 "Wireless debugging didn't start on $serial. If Android asked to allow it on this network, allow it and try again."
}

start_tcpip() {
  timeout 8 adb -s "$1" tcpip 5555 >/dev/null 2>&1 || die 1 "Couldn't switch $1 to ADB over TCP."
  printf '5555'
}

# adbd restarts after `adb tcpip`, so the first connects can be refused.
# An authentication failure is final; retrying won't change it.
connect_wireless() {
  local address="$1" hint="$2" reply=""
  for _ in {1..6}; do
    reply="$(timeout 10 adb connect "$address" 2>&1)"
    [[ "$reply" =~ [Aa]uthenticat ]] && die 4 "Couldn't authenticate to $address. $hint"
    [[ "$reply" =~ connected\ to && ! "$reply" =~ failed|unable|cannot ]] && return 0
    sleep "$poll_delay"
  done
  die 4 "Couldn't connect to $address: ${reply:-no answer}"
}

# A connected but untrusted transport shows up as "unauthorized".
wait_until_ready() {
  local address="$1" hint="$2" state=""
  for _ in {1..12}; do
    state="$(timeout 4 adb -s "$address" get-state 2>/dev/null)"
    [[ "$state" == device ]] && return 0
    [[ "$state" == unauthorized ]] && die 4 "$address connected but isn't authorized. $hint"
    sleep "$poll_delay"
  done
  die 4 "$address connected but didn't become ready (state '${state:-unknown}')."
}

serial="${1:-}"
valid_serial "$serial"
sdk="$(device_shell "$serial" 4 getprop ro.build.version.sdk)"
[[ "$sdk" =~ ^[0-9]+$ ]] || die 1 "Couldn't read the Android version of $serial (got '$sdk'); expected an SDK number."
host="$(wifi_address "$serial")" || die 2 "$serial isn't on Wi-Fi. Join the same network as this computer, then try again."
if ((sdk >= 30)); then
  port="$(start_tls "$serial")" || exit $?
  hint="$tls_hint"
else
  port="$(start_tcpip "$serial")" || exit $?
  hint="Accept the debugging prompt on Android, then try again."
fi
connect_wireless "$host:$port" "$hint"
wait_until_ready "$host:$port" "$hint"
printf 'Connected to %s. You can unplug the cable.\n' "$host:$port"
