#!/usr/bin/env bash
# Resolve Android DNS-SD services through Avahi, independently of ADB.
# stdout: resolved avahi-browse --parsable records, one per line.
# stderr: diagnostics. Nonzero exit may accompany partial resolved results.
set -euo pipefail
export LC_ALL=C

for dependency in avahi-browse timeout awk; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'DroidLink mDNS: missing %s. Install Avahi and GNU coreutils.\n' "$dependency" >&2
    exit 1
  fi
done

scan_dir="$(mktemp -d "${TMPDIR:-/tmp}/droidlink-mdns.XXXXXXXX")"
scan_pids=()
cleanup() {
  # Stop only children belonging to this scan; timeout forwards TERM to Avahi.
  for scan_pid in "${scan_pids[@]}"; do
    kill -TERM "$scan_pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  # Explicit files only, inside the private directory created above.
  for index in 0 1 2; do
    rm -f -- "$scan_dir/$index.out" "$scan_dir/$index.err"
  done
  rmdir -- "$scan_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

service_types=(_adb._tcp _adb-tls-connect._tcp _adb-tls-pairing._tcp)
for index in "${!service_types[@]}"; do
  timeout --signal=TERM --kill-after=1s 8s \
    avahi-browse --resolve --parsable --no-db-lookup --terminate \
      "${service_types[$index]}" \
      >"$scan_dir/$index.out" 2>"$scan_dir/$index.err" &
  scan_pids+=("$!")
done

scan_status=0
for index in "${!service_types[@]}"; do
  query_status=0
  wait "${scan_pids[$index]}" || query_status=$?
  # Do not signal an already reaped child during cleanup.
  unset 'scan_pids[index]'
  if (( query_status != 0 )); then
    scan_status=1
    if (( query_status == 124 || query_status == 137 )); then
      printf 'DroidLink mDNS: %s discovery timed out; showing resolved results.\n' "${service_types[$index]}" >&2
    else
      printf 'DroidLink mDNS: %s discovery failed. Check that avahi-daemon is running.\n' "${service_types[$index]}" >&2
    fi
  fi
  if [[ -s "$scan_dir/$index.err" ]]; then
    awk 'NR <= 8 { print }' "$scan_dir/$index.err" >&2
  fi
done

# + records are announcements without an address; - records are removals.
# Keep only currently resolved records. Decode escaped names in QML, never as
# shell source. TXT data is not needed and is omitted from the output.
awk -F ';' '
  $1 == "=" && NF >= 9 {
    key = $2 FS $3 FS $4 FS $5 FS $6
    row[key] = $1 FS $2 FS $3 FS $4 FS $5 FS $6 FS $7 FS $8 FS $9
  }
  $1 == "-" { delete row[$2 FS $3 FS $4 FS $5 FS $6] }
  END { for (key in row) print row[key] }
' "$scan_dir/0.out" "$scan_dir/1.out" "$scan_dir/2.out"
exit "$scan_status"
