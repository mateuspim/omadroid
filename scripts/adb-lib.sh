# Sourced by device-power.sh and go-wireless.sh: error exits and bounded
# `adb shell` calls against one device.

# Prints the message on stderr, where the plugin reads it, and exits with code.
die() {
  local code="$1"
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

valid_serial() {
  [[ "$1" =~ ^[A-Za-z0-9._:@-]{1,128}$ ]] || die 1 "Unexpected adb serial '$1'; expected letters, digits and . _ : @ -."
}

# device_shell SERIAL SECONDS COMMAND... → the command's stdout without CRs.
device_shell() {
  timeout "${2:-4}" adb -s "$1" shell "${@:3}" 2>/dev/null | tr -d '\r'
}
