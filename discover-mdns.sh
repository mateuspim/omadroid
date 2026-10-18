#!/usr/bin/env bash
# Follow Android DNS-SD services through Avahi, independently of ADB, until
# terminated. One browser per service type stays open, so devices appear and
# leave as Avahi sees them instead of on a rescan.
# stdout: avahi-browse --parsable lines as they arrive ("=" resolved, "-" removed).
# stderr: diagnostics. Exits nonzero once any browser stops.
set -euo pipefail
export LC_ALL=C

for dependency in avahi-browse:Avahi setpriv:util-linux; do
  if ! command -v "${dependency%%:*}" >/dev/null 2>&1; then
    printf 'OmaDroid mDNS: missing %s. Install %s.\n' "${dependency%%:*}" "${dependency#*:}" >&2
    exit 1
  fi
done

browser_pids=()
browser_types=()
stop_browsers() {
  # Stop only browsers started by this helper.
  for browser_pid in "${browser_pids[@]}"; do
    kill -TERM "$browser_pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap stop_browsers EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# avahi-browse flushes each record, and pipe writes of one line are atomic,
# so the three browsers can share stdout. Escaped names are decoded in QML,
# never as shell source. TXT data is kept for the device model (name=...).
# A SIGKILLed helper (the shell quitting) runs no trap; the parent-death
# signal still stops its browsers.
for service_type in _adb._tcp _adb-tls-connect._tcp _adb-tls-pairing._tcp; do
  setpriv --pdeathsig TERM avahi-browse --resolve --parsable --no-db-lookup "$service_type" &
  browser_pids+=("$!")
  browser_types+=("$service_type")
done

browser_status=0
wait -n -p stopped_pid "${browser_pids[@]}" || browser_status=$?
for index in "${!browser_pids[@]}"; do
  [[ "${browser_pids[$index]}" == "${stopped_pid:-}" ]] || continue
  # Already reaped; never signal its PID during cleanup.
  unset 'browser_pids[index]'
  printf 'OmaDroid mDNS: discovery stopped (%s exited with %s). Check that avahi-daemon is running.\n' \
    "${browser_types[$index]}" "$browser_status" >&2
done
exit 1
