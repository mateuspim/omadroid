#!/usr/bin/env bash
# Reads the labels of apps that `scrcpy --list-apps` doesn't name (no launcher
# icon, e.g. a keyboard) from their APKs, for the Sound tab's Apps list.
#
#   app-labels.sh SERIAL SERIALNO < packages, one per line
#
# device-volume.sh starts it in the background, so a status read never waits
# for an APK. Packages come on stdin and go to the device on stdin: they name
# installed apps, and arguments are visible to other users. Each label is
# appended to labels_file; a package whose APK can't be read goes to
# failed_labels_file, so it isn't pulled again on every read.
#
# The device is untrusted (omacom/omarchy-plugin-marketplace#13776): the pull
# is capped on the host, the parser is bounded in time (here) and in memory,
# CPU and decoded bytes (apk-label.py), and the work folder is removed on
# every exit. device-volume.sh bounds the whole run.
set -uo pipefail
export LC_ALL=C

script_dir="$(dirname -- "${BASH_SOURCE[0]}")"
source "$script_dir/adb-lib.sh"
source "$script_dir/app-cache-lib.sh"
# Bigger APKs aren't pulled (games ship gigabytes); 64 packages per run.
# The device checks the size, and the host enforces it again while streaming
# (pull_apk): a compromised device can ignore its check and send forever.
# 300 MiB holds ordinary apps' base APKs, and the host keeps one at a time.
max_apk_bytes=$(at_most "${OMADROID_LABEL_MAX_BYTES:-}" $((300 * 1024 * 1024)))
max_packages=64
# apk-label.py reads two members; seconds for it, past its own 20 s CPU cap.
parse_seconds=$(at_most "${OMADROID_LABEL_PARSE_SECONDS:-}" 30)
# This run's private work folder, inside the label cache; see make_work.
work=""

# Prints the package's base APK on stdout, or nothing when it has none or it
# is too big. `pm path` lists the base first: `base.apk` for installed and
# updated apps, `/system/app/NAME/NAME.apk` for untouched preinstalled ones.
# The device path stays on the device. --foreground keeps adb in this run's
# process group, so device-volume.sh's timeout stops it with the rest.
fetch_apk() {
  printf '%s\n' "p=\$(pm path '$2' | sed -n '1s/^package:\\(.*\\.apk\\)\$/\\1/p')" \
    "[ -n \"\$p\" ] && [ \"\$(stat -c %s \"\$p\")\" -le $max_apk_bytes ] && cat \"\$p\"" 'exit' |
    timeout --foreground 180 adb -s "$1" shell -T 2>/dev/null
}

# Writes PACKAGE's APK to FILE through `head -c`, so the host never stores
# more than max_apk_bytes + 1; reaching that byte refuses the APK (adb then
# stops on SIGPIPE). Fails for an empty or refused APK. fd 9 (the lock)
# isn't passed on, so a leftover child can't hold it.
pull_apk() {
  local size
  { fetch_apk "$1" "$2" | head -c $((max_apk_bytes + 1)) >"$3"; } 9>&- || return 1
  size="$(stat -c %s -- "$3")" || return 1
  ((size > 0 && size <= max_apk_bytes))
}

# Prints the label of PACKAGE's APK, read in this run's work folder.
read_label() {
  local serial="$1" package="$2" apk="$work/base.apk" status
  pull_apk "$serial" "$package" "$apk" &&
    timeout --foreground -k 2 "$parse_seconds" python3 -I "$script_dir/apk-label.py" "$apk" 2>/dev/null 9>&-
  status=$?
  rm -f -- "$apk"
  return "$status"
}

# Creates this run's work folder in the private label cache, first removing
# any a killed run left (only the lock holder makes one, so all are stale),
# and removes it on every exit: done, timed out or interrupted. TERM, INT
# and HUP are trapped into an exit: left to their default, bash killed while
# waiting on a command substitution sometimes skips the EXIT trap. The trap
# runs once the current pull ends, which the same signal ends (adb runs in
# this process group). Only KILL skips it; the next run sweeps that folder.
make_work() {
  find "$1" -maxdepth 1 -name '.work-*' -type d -exec rm -rf -- {} + 2>/dev/null
  trap 'exit 143' TERM INT HUP
  trap 'rm -rf -- "$work"' EXIT
  work="$(mktemp -d -p "$1" .work-XXXXXX)" || die 1 "Couldn't create a work folder in $1."
}

# True when PACKAGE already has a label or a recent failure.
already_read() {
  APP_PKG="$1" awk -F'\t' '$1 == ENVIRON["APP_PKG"] { found = 1 } END { exit !found }' \
    "$2" "$3" 2>/dev/null
}

# Reads each new package's label, appending it or recording the failure.
read_labels() {
  local serial="$1" labels="$2" failed="$3" package label count=0
  while IFS= read -r package && ((count++ < max_packages)); do
    [[ "$package" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]] || continue
    already_read "$package" "$labels" "$failed" && continue
    if label="$(read_label "$serial" "$package")" && [[ -n "$label" && "$label" != *$'\t'* ]]; then
      printf '%s\t%s\n' "$package" "$label" >>"$labels"
    else
      printf '%s\n' "$package" >>"$failed"
    fi
  done
}

main() {
  local serial="$1" serialno="$2" labels failed
  valid_serial "$serial"
  [[ "$serialno" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die 1 "Unexpected device serial number '$serialno'; expected 1-64 letters, digits, . _ -."
  command -v python3 >/dev/null 2>&1 || die 1 "Reading app labels needs python3."
  labels="$(labels_file "$serialno")"
  failed="$(failed_labels_file "$serialno")"
  private_cache "${labels%/*}"
  # One reader per phone; a second start while it runs has nothing to add.
  exec 9>"$labels.lock"
  flock -n 9 || exit 0
  find "$failed" -mmin +1440 -delete 2>/dev/null
  make_work "${labels%/*}"
  read_labels "$serial" "$labels" "$failed"
}

main "${1:-}" "${2:-}"
