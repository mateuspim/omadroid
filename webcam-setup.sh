#!/usr/bin/env bash
# Run privileged setup only after the user clicks the webcam setup action.
# A visible terminal lets Omarchy's package helper and sudo ask for a password.
set -euo pipefail
etc_dir="${OMADROID_ETC:-/etc}"
load_conf="$etc_dir/modules-load.d/v4l2loopback.conf"
options_conf="$etc_dir/modprobe.d/v4l2loopback.conf"

# Loads one output now and at every boot. Existing v4l2loopback config is the
# user's own (other numbers, labels or devices), so it is never overwritten.
enable_output() {
  echo 'Enabling a virtual camera output...'
  sudo modprobe v4l2loopback devices=1 exclusive_caps=1
  if [[ -e "$load_conf" || -e "$options_conf" ]]; then
    echo "Kept your existing v4l2loopback boot config ($load_conf, $options_conf)."
  else
    echo 'Loading it at every boot...'
    printf 'v4l2loopback\n' | sudo tee "$load_conf" >/dev/null
    printf 'options v4l2loopback devices=1 exclusive_caps=1\n' | sudo tee "$options_conf" >/dev/null
  fi
  echo "Ready. Return to OmaDroid and press Refresh in the device's Webcam section."
}

# In the setup terminal: a success closes after 10 s (Enter closes at once);
# a failure waits for Enter so the sudo or package error stays readable.
pause_before_close() {
  local status=$?
  if (( status == 0 )); then
    read -rt 10 -p 'Closing in 10 s (Enter closes now).' _ || true
  else
    echo 'Setup did not finish; see the messages above.'
    read -rp 'Press Enter to close.' _ || true
  fi
}

case "${1:-}" in
  open)
    [[ "${2:-}" == install || "${2:-}" == load ]] || { echo 'Invalid setup action.' >&2; exit 2; }
    source "$(dirname -- "$0")/terminal-lib.sh"
    terminal_available || { echo 'No terminal is available. Install foot or set an Omarchy default terminal.' >&2; exit 127; }
    # Omarchy floats and centers org.omarchy.terminal in its built-in rules.
    # The setup asks for Enter itself, so the window closes when it is read.
    terminal_hold=0
    launch_terminal org.omarchy.terminal 'OmaDroid webcam setup' bash "$0" "$2"
    ;;
  install)
    [[ -t 0 && -t 1 ]] && trap pause_before_close EXIT
    echo 'Installing the v4l2loopback driver with Omarchy...'
    omarchy pkg add v4l2loopback-dkms
    enable_output
    ;;
  load)
    [[ -t 0 && -t 1 ]] && trap pause_before_close EXIT
    enable_output
    ;;
  *) echo 'Usage: webcam-setup.sh open install|load' >&2; exit 2 ;;
esac
