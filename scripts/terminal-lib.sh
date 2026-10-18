# Sourced by session.sh and webcam-setup.sh. Foot is preferred: each window is
# its own process and empty arguments survive, so the hidden session terminal
# stays separate from the user's own terminals. Without foot, OmaDroid uses
# the Omarchy default terminal. OMADROID_FOOT lets tests choose the binary.
foot_bin="${OMADROID_FOOT:-foot}"

terminal_available() {
  command -v "$foot_bin" >/dev/null 2>&1 && return 0
  command -v omarchy >/dev/null 2>&1 && command -v xdg-terminal-exec >/dev/null 2>&1 && xdg-terminal-exec --print-id >/dev/null 2>&1
}

# Seconds a launched terminal may take to run its command. Foot starts in a
# fraction of a second; a cold Ghostty or Alacritty (GPU setup, config load)
# took longer than 3 s, and the launch was reported as failed while it came up.
terminal_start_limit() {
  command -v "$foot_bin" >/dev/null 2>&1 && printf 3 || printf 8
}

# Usage: launch_terminal APP_ID TITLE COMMAND... (detached, held open on exit;
# set terminal_hold=0 when COMMAND asks before closing on its own)
terminal_hold=1
launch_terminal() {
  local app_id="$1" title="$2" hold=()
  shift 2
  (( terminal_hold )) && hold=(--hold)
  if command -v "$foot_bin" >/dev/null 2>&1; then
    setsid -f "$foot_bin" --app-id="$app_id" --title="$title" "${hold[@]}" -- "$@" </dev/null >/dev/null 2>&1
  else
    setsid -f omarchy launch terminal --app-id="$app_id" "${hold[@]}" --title="$title" -- "$@" </dev/null >/dev/null 2>&1
  fi
}
