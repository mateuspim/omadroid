# Sourced by session.sh and device-power.sh: the per-user runtime folder and
# process identity checks shared by every process OmaDroid leaves running.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/omadroid-${UID}"
mkdir -p -m 700 -- "$runtime_dir"
chmod 700 -- "$runtime_dir"

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
