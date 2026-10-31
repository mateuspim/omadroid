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
set -uo pipefail
export LC_ALL=C

script_dir="$(dirname -- "${BASH_SOURCE[0]}")"
source "$script_dir/adb-lib.sh"
source "$script_dir/app-cache-lib.sh"
# Bigger APKs aren't pulled (games ship gigabytes); 64 packages per run.
max_apk_bytes=$((300 * 1024 * 1024))
max_packages=64

# Prints the package's base APK on stdout, or nothing when it has none or it
# is too big. `pm path` lists the base first: `base.apk` for installed and
# updated apps, `/system/app/NAME/NAME.apk` for untouched preinstalled ones.
# The device path stays on the device.
fetch_apk() {
  printf '%s\n' "p=\$(pm path '$2' | sed -n '1s/^package:\\(.*\\.apk\\)\$/\\1/p')" \
    "[ -n \"\$p\" ] && [ \"\$(stat -c %s \"\$p\")\" -le $max_apk_bytes ] && cat \"\$p\"" 'exit' |
    timeout 180 adb -s "$1" shell -T 2>/dev/null
}

# Prints the label of PACKAGE's APK, read in a private temporary folder.
read_label() {
  local serial="$1" package="$2" work status
  work="$(mktemp -d)" || return 1
  fetch_apk "$serial" "$package" >"$work/base.apk" &&
    [[ -s "$work/base.apk" ]] &&
    python3 -I "$script_dir/apk-label.py" "$work/base.apk" 2>/dev/null
  status=$?
  rm -rf -- "$work"
  return "$status"
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
  read_labels "$serial" "$labels" "$failed"
}

main "${1:-}" "${2:-}"
