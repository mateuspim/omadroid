#!/usr/bin/env bash
# Keep scrcpy in a terminal outside the Omarchy shell process. All widget
# instances inspect the same session, including instances created after reload.
set -euo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/droidlink-${UID}"
mkdir -p -m 700 -- "$runtime_dir"
chmod 700 -- "$runtime_dir"
state_file="$runtime_dir/session"
lock_file="$runtime_dir/lock"

start_time() {
  [[ -r "/proc/$1/stat" ]] || return 1
  # /proc/PID/stat has a parenthesized command, possibly containing spaces.
  local rest
  rest="$(<"/proc/$1/stat")"
  rest="${rest##*) }"
  set -- $rest
  [[ "$1" != Z ]] || return 1
  printf '%s' "${20}"
}

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
      rm -f -- "$state_file"
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
    if ! command -v omarchy >/dev/null 2>&1 || ! command -v xdg-terminal-exec >/dev/null 2>&1 || ! xdg-terminal-exec --print-id >/dev/null 2>&1; then
      echo 'No Omarchy default terminal is available.' >&2
      exit 127
    fi
    with_lock
    if read_session; then
      echo 'A DroidLink session is already active.' >&2
      exit 1
    fi
    rm -f -- "$state_file"
    # The terminal is detached from Quickshell. Its child execs scrcpy, so
    # terminal output and errors remain visible even after a shell restart.
    setsid -f omarchy launch terminal --app-id=org.omarchy.droidlink --hold --title=DroidLink -- bash "$0" run "$serial" "$audio" "$recording" -- "$@" </dev/null >/dev/null 2>&1
    flock -u 9
    for ((attempt=0; attempt<30; attempt++)); do
      if [[ -f "$state_file" ]]; then
        echo 'Session started in the hidden DroidLink terminal.'
        exit 0
      fi
      sleep 0.1
    done
    echo 'The Omarchy terminal did not start scrcpy. Check your default terminal.' >&2
    exit 1
    ;;
  run)
    shift
    serial="$1" audio="$2" recording="$3"
    shift 3
    [[ "$1" == -- ]] || exit 2
    shift
    with_lock
    if read_session; then
      echo 'A DroidLink session is already active.' >&2
      exit 1
    fi
    printf '%s\n%s\n%s\n%s\n%s\n' "$$" "$(start_time "$$")" "$serial" "$audio" "$recording" > "$state_file"
    flock -u 9
    exec 9>&-
    printf 'DroidLink: running %q ' "$@"
    printf '\n'
    exec "$@"
    ;;
  stop)
    with_lock
    if ! read_session; then
      rm -f -- "$state_file"
      echo 'No active DroidLink session.'
      exit 0
    fi
    pid="${state[0]}" birth="${state[1]}"
    kill -TERM "$pid"
    flock -u 9
    for ((attempt=0; attempt<40; attempt++)); do
      [[ "$(start_time "$pid" 2>/dev/null || true)" == "$birth" ]] || {
        echo 'Session stopped.'
        exit 0
      }
      sleep 0.1
    done
    if [[ "$(start_time "$pid" 2>/dev/null || true)" == "$birth" ]]; then
      kill -KILL "$pid" 2>/dev/null || true
      echo 'Session force-stopped after scrcpy did not exit cleanly.'
    fi
    ;;
  *) echo 'Usage: session.sh check|status|launch|stop' >&2; exit 2 ;;
esac
