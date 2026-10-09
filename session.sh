#!/usr/bin/env bash
# Keep scrcpy in a terminal outside the Omarchy shell process. All widget
# instances inspect the same session, including instances created after reload.
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/proc-lib.sh"
state_file="$runtime_dir/session"
lock_file="$runtime_dir/lock"
# Holds the serial whose rotation lock DroidLink set during the current session.
rotation_file="$runtime_dir/rotation"
# Written by `run` once the terminal reached it. `launch` waits for this, not
# for the state file, which a watching widget removes as soon as a scrcpy that
# failed immediately has exited.
started_file="$runtime_dir/started"

read_session() {
  local actual
  [[ -f "$state_file" ]] || return 1
  mapfile -t state < "$state_file"
  [[ ${#state[@]} -eq 5 && ${state[0]} =~ ^[0-9]+$ && ${state[1]} =~ ^[0-9]+$ ]] || return 1
  actual="$(start_time "${state[0]}" 2>/dev/null)" || return 1
  [[ "$actual" == "${state[1]}" ]]
}

with_lock() {
  exec 9>"$lock_file"
  flock -x 9
}

# Android keeps a user-rotation lock after scrcpy exits. Release only a lock
# DroidLink set, never one chosen on the phone. Detached so a missing device
# cannot stall the status poll that holds the session lock.
release_owned_rotation() {
  local serial
  [[ -f "$rotation_file" ]] || return 0
  serial="$(<"$rotation_file")"
  rm -f -- "$rotation_file"
  [[ "$serial" ]] || return 0
  setsid -f timeout 5 adb -s "$serial" shell wm user-rotation free </dev/null >/dev/null 2>&1 || true
}

# Send the diagnostic terminal straight to a hidden workspace so it never
# flashes or takes focus, without asking users to edit their Hyprland config.
# The rule is named so each launch replaces it. Best effort: without Hyprland
# the terminal simply stays visible.
hide_terminal() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl eval 'hl.window_rule({ name = "droidlink-terminal", match = { class = "^org\\.omarchy\\.droidlink$" }, workspace = "special:droidlink silent", no_initial_focus = true })' >/dev/null 2>&1 || true
}

# Every path that discovers a finished session goes through here.
end_session() {
  rm -f -- "$state_file"
  release_owned_rotation
}

# Prints "free" or "lock N", plus "owned" when DroidLink set the lock.
# Android stores user_rotation as null until it is first set; that means 0.
query_rotation() {
  local reply auto="" user=""
  reply="$(timeout 4 adb -s "$1" shell 'settings get system accelerometer_rotation; settings get system user_rotation' 2>&1)" || {
    printf '%s\n' "$reply" >&2
    return 1
  }
  reply="${reply//$'\r'/}"
  { read -r auto; read -r user; } <<<"$reply" || true
  [[ "$user" == null ]] && user=0
  if [[ "$auto" == 1 ]]; then
    echo free
  elif [[ "$auto" == 0 && "$user" =~ ^[0-3]$ ]]; then
    echo "lock $user"
    [[ -f "$rotation_file" ]] && echo owned
  else
    printf 'Unexpected rotation settings %q; expected accelerometer_rotation 0|1 and user_rotation 0-3.\n' "$reply" >&2
    return 1
  fi
  return 0
}

# adb can exit 0 while wm reports an error, so the output is checked too.
set_rotation() {
  local reply
  reply="$(timeout 4 adb -s "$1" shell wm user-rotation "${@:2}" 2>&1)" &&
    ! grep -qiE 'failed|error|unknown command|permission denied' <<<"$reply" || {
    printf '%s\n' "${reply:-adb returned no diagnostic}" >&2
    return 1
  }
}

case "${1:-}" in
  check)
    missing=()
    for program in adb scrcpy; do
      command -v "$program" >/dev/null 2>&1 || missing+=("$program")
    done
    if ! command -v omarchy >/dev/null 2>&1 || ! command -v xdg-terminal-exec >/dev/null 2>&1 || ! xdg-terminal-exec --print-id >/dev/null 2>&1; then
      missing+=("Omarchy default terminal")
    fi
    printf '%s\n' "${missing[@]}"
    ;;
  status)
    with_lock
    if read_session; then
      printf 'active\n%s\n%s\n%s\n%s\n' "${state[2]}" "${state[3]}" "${state[4]}" "${state[0]}"
    else
      end_session
      printf 'inactive\n'
    fi
    ;;
  launch)
    shift
    [[ $# -ge 5 ]] || { echo 'Invalid launch request.' >&2; exit 2; }
    serial="$1" audio="$2" recording="$3"
    shift 3
    [[ "$1" == -- ]] || { echo 'Invalid launch separator.' >&2; exit 2; }
    shift
    [[ "$serial" && "$serial" != *$'\n'* && "$recording" != *$'\n'* && "$audio" =~ ^[01]$ && "$1" == scrcpy ]] || {
      echo 'Invalid session fields.' >&2; exit 2;
    }
    for program in adb scrcpy; do
      command -v "$program" >/dev/null 2>&1 || { echo "Missing $program. Install it before launching." >&2; exit 127; }
    done
    # scrcpy would otherwise die in the hidden terminal with no visible reason.
    if [[ "$recording" ]]; then
      folder="$(dirname -- "$recording")"
      [[ -d "$folder" ]] || { echo "Recording folder $folder does not exist. Create it or choose another folder." >&2; exit 1; }
      [[ -w "$folder" ]] || { echo "Recording folder $folder is not writable. Choose another folder." >&2; exit 1; }
    fi
    if ! command -v omarchy >/dev/null 2>&1 || ! command -v xdg-terminal-exec >/dev/null 2>&1 || ! xdg-terminal-exec --print-id >/dev/null 2>&1; then
      echo 'No Omarchy default terminal is available.' >&2
      exit 127
    fi
    with_lock
    if read_session; then
      echo 'A DroidLink session is already active.' >&2
      exit 1
    fi
    end_session
    rm -f -- "$started_file"
    hide_terminal
    # Terminals may drop or re-split arguments on their way to the command
    # (Ghostty's hold mode drops the empty recording path), so the request
    # travels in a NUL-separated file and only its path goes through argv.
    request="$(mktemp -- "$runtime_dir/request.XXXXXX")"
    printf '%s\0' "$serial" "$audio" "$recording" "$@" > "$request"
    # The terminal is detached from Quickshell. Its child execs scrcpy, so
    # terminal output and errors remain visible even after a shell restart.
    # fd 9 is closed so the terminal never holds the session lock.
    setsid -f omarchy launch terminal --app-id=org.omarchy.droidlink --hold --title=DroidLink -- bash "$0" run "$request" </dev/null >/dev/null 2>&1 9>&-
    flock -u 9
    for ((attempt=0; attempt<30; attempt++)); do
      if [[ -f "$started_file" ]]; then
        rm -f -- "$started_file"
        rm -f -- "$request"
        echo 'Session started in the hidden DroidLink terminal.'
        exit 0
      fi
      sleep 0.1
    done
    rm -f -- "$request"
    echo 'The Omarchy terminal did not start scrcpy. Check your default terminal.' >&2
    exit 1
    ;;
  run)
    [[ "${2:-}" == "$runtime_dir"/request.* && -f "$2" ]] || { echo 'Invalid run request.' >&2; exit 2; }
    mapfile -d '' -t request < "$2"
    rm -f -- "$2"
    [[ ${#request[@]} -ge 4 ]] || { echo 'Invalid run request.' >&2; exit 2; }
    serial="${request[0]}" audio="${request[1]}" recording="${request[2]}"
    set -- "${request[@]:3}"
    with_lock
    if read_session; then
      echo 'A DroidLink session is already active.' >&2
      exit 1
    fi
    printf '%s\n%s\n%s\n%s\n%s\n' "$$" "$(start_time "$$")" "$serial" "$audio" "$recording" > "$state_file"
    : > "$started_file"
    flock -u 9
    exec 9>&-
    printf 'DroidLink: running %q ' "$@"
    printf '\n'
    exec "$@"
    ;;
  stop)
    with_lock
    if ! read_session; then
      end_session
      echo 'No active DroidLink session.'
      exit 0
    fi
    pid="${state[0]}" birth="${state[1]}"
    # scrcpy may exit on its own between read_session and here.
    kill -TERM "$pid" 2>/dev/null || true
    flock -u 9
    alive() { [[ "$(start_time "$pid" 2>/dev/null || true)" == "$birth" ]]; }
    wait_gone() {
      local attempt
      for ((attempt=0; attempt<$1; attempt++)); do
        alive || return 0
        sleep 0.1
      done
      ! alive
    }
    if wait_gone 40; then
      message='Session stopped.'
    else
      kill -KILL "$pid" 2>/dev/null || true
      # Clean up only once the process is gone, so read_session agrees.
      wait_gone 20 || true
      message='Session force-stopped after scrcpy did not exit cleanly.'
    fi
    with_lock
    read_session || end_session
    echo "$message"
    ;;
  path)
    # Widgets watch this file instead of polling `status`: it appears when a
    # session starts and disappears when one ends.
    printf '%s\n' "$state_file"
    ;;
  wait)
    # Block until the running session ends, then clean it up (rotation lock
    # included) the same way status would. One idle process per session
    # replaces a status poll.
    with_lock
    if ! read_session; then
      end_session
      echo inactive
      exit 0
    fi
    pid="${state[0]}" birth="${state[1]}"
    flock -u 9
    # util-linux waitpid sleeps on a pidfd; the loop covers its absence and a
    # PID that is already gone.
    command -v waitpid >/dev/null 2>&1 && waitpid "$pid" >/dev/null 2>&1 || true
    while [[ "$(start_time "$pid" 2>/dev/null || true)" == "$birth" ]]; do
      sleep 1
    done
    with_lock
    read_session || end_session
    echo inactive
    ;;
  rotate)
    action="${2:-}" rotation="${3:-}"
    case "$action" in
      lock) [[ "$rotation" =~ ^[0-3]$ ]] || { echo "Invalid rotation '$rotation'; expected 0-3." >&2; exit 2; } ;;
      free | query) ;;
      *) echo "Invalid rotate action '$action'; expected lock, free or query." >&2; exit 2 ;;
    esac
    with_lock
    read_session || { echo 'No active DroidLink session.' >&2; exit 1; }
    serial="${state[2]}"
    # adb may take seconds; status polls must not wait behind it.
    flock -u 9
    [[ "$action" == query ]] && { query_rotation "$serial"; exit; }
    set_rotation "$serial" $action $rotation || exit 1
    with_lock
    if [[ "$action" == lock ]]; then
      printf '%s\n' "$serial" > "$rotation_file"
      read_session || end_session
    else
      rm -f -- "$rotation_file"
    fi
    ;;
  *) echo 'Usage: session.sh check|status|path|wait|launch|stop|rotate lock 0-3|free|query' >&2; exit 2 ;;
esac
