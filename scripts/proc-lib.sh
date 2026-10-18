# Sourced by session.sh, device-power.sh and webcam-preview.sh: the per-user runtime folder and
# process identity checks shared by every process OmaDroid leaves running.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/omadroid-${UID}"

# PIDs recorded here are signalled later, so the folder must be this user's
# alone. Without XDG_RUNTIME_DIR it falls back to the shared /tmp, where another
# user can create the name first; refuse a symlink or a folder owned by
# someone else (plugins.omarchy.org baseline: owner-only PID state).
# Usage: ensure_runtime_dir || exit 1
ensure_runtime_dir() {
  mkdir -p -m 700 -- "$runtime_dir" 2>/dev/null
  if [[ -L "$runtime_dir" || ! -d "$runtime_dir" || ! -O "$runtime_dir" ]]; then
    echo "Runtime folder '$runtime_dir' must be a directory owned by $(id -un), not a symlink; refusing to use it." >&2
    return 1
  fi
  chmod 700 -- "$runtime_dir"
}
ensure_runtime_dir || exit 1

# Prints a process's start time, so a recorded PID reused by another process
# is not mistaken for ours. Fails for missing and zombie processes.
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
