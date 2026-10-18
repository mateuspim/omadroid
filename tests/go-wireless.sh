#!/usr/bin/env bash
# go-wireless.sh against a fake adb that simulates Wireless debugging. Nothing
# here touches a real device.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-wireless.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-wireless.* ]] && rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/device"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
chmod +x "$test_dir/bin/adb"
export PATH="$test_dir/bin:$PATH" OMADROID_WIRELESS_DIR="$test_dir/device" OMADROID_POLL_DELAY=0.01
device="$test_dir/device"
fail() {
  echo "OMADROID_WIRELESS_FAILED: $*" >&2
  exit 1
}
# reset_device SDK ENABLED: a phone on Wi-Fi (and mobile data) with a clean log.
reset_device() {
  rm -f "$device/"*
  printf '%s' "$1" >"$device/sdk"
  printf '%s' "$2" >"$device/enabled"
  printf '41234' >"$device/port"
  printf '%s\n' '1: lo    inet 127.0.0.1/8 scope host lo' \
    '12: rmnet_data0    inet 10.20.30.40/30 scope global rmnet_data0' \
    '47: wlan0    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0' >"$device/addresses"
}
# go EXPECTED_CODE SERIAL → stdout and stderr of the run in $out.
go() {
  local expected="$1" code=0
  out="$(bash "$repo_dir/go-wireless.sh" "$2" 2>&1)" || code=$?
  [[ "$code" == "$expected" ]] || fail "go-wireless $2 exited $code; expected $expected: $out"
}

# Android 11+: turns Wireless debugging on and connects to its TLS port.
reset_device 34 0
go 0 USB123
[[ "$out" == 'Connected to 192.168.1.42:41234. You can unplug the cable.' ]] || fail "TLS message: $out"
[[ "$(cat "$device/enabled")" == 1 ]] || fail "Wireless debugging turned on"
grep -qx 'connect 192.168.1.42:41234' "$device/log" || fail "connects to the TLS port on wlan0"
! grep -q tcpip "$device/log" || fail "Android 11+ never switches to unencrypted TCP"

# Already on: nothing is changed on the device.
reset_device 34 1
go 0 USB123
! grep -q 'settings put' "$device/log" || fail "an enabled device is left as is"

# A port left from an earlier session isn't trusted: it waits for the new one.
reset_device 34 0
printf '41234' >"$device/stale-port"
printf '45678' >"$device/port"
go 0 USB123
grep -qx 'connect 192.168.1.42:45678' "$device/log" || fail "stale port skipped: $(cat "$device/log")"

# Wireless debugging never publishes a port.
reset_device 34 0
printf '' >"$device/port"
go 3 USB123
[[ "$out" == *"Wireless debugging didn't start"* ]] || fail "start failure message: $out"

# Older Android falls back to adb tcpip.
reset_device 29 0
go 0 USB123
grep -qx -- '-s USB123 tcpip 5555' "$device/log" || fail "tcpip on Android 10"
grep -qx 'connect 192.168.1.42:5555' "$device/log" || fail "connects to 5555"

# No Wi-Fi: mobile data alone doesn't count.
reset_device 34 0
printf '%s\n' '12: rmnet_data0    inet 10.20.30.40/30 scope global rmnet_data0' >"$device/addresses"
go 2 USB123
[[ "$out" == *"isn't on Wi-Fi"* ]] || fail "no Wi-Fi message: $out"
! grep -q 'settings put' "$device/log" || fail "nothing is enabled without Wi-Fi"

# A host the device doesn't trust over TLS is pointed at QR pairing.
reset_device 34 0
OMADROID_TEST_CASE=untrusted go 4 USB123
[[ "$out" == *"isn't authorized"*"Pair with QR code"* ]] || fail "untrusted hint: $out"

# Serials are checked before adb sees them.
reset_device 34 0
go 1 'bad serial;'
[[ ! -e "$device/log" ]] || fail "a bad serial never reaches adb"

echo OMADROID_WIRELESS_OK
