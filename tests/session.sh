#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-session.XXXXXX)"
cleanup() {
  XDG_RUNTIME_DIR="$test_dir/runtime" bash "$repo_dir/session.sh" stop >/dev/null 2>&1 || true
  [[ "$test_dir" == /tmp/droidlink-session.* ]] && rm -rf -- "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/bin" "$test_dir/runtime"
cp "$repo_dir/tests/mock-omarchy.sh" "$test_dir/bin/omarchy"
cp "$repo_dir/tests/mock-xdg-terminal-exec.sh" "$test_dir/bin/xdg-terminal-exec"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-hyprctl.sh" "$test_dir/bin/hyprctl"
cp "$repo_dir/tests/mock-foot.sh" "$test_dir/mock-foot"
chmod +x "$test_dir/bin/omarchy" "$test_dir/bin/xdg-terminal-exec" "$test_dir/bin/scrcpy" "$test_dir/bin/adb" "$test_dir/bin/hyprctl" "$test_dir/mock-foot"
# Most launches cover the Omarchy fallback; the real foot must never start.
export DROIDLINK_FOOT="$test_dir/no-foot"
export PATH="$test_dir/bin:$PATH" XDG_RUNTIME_DIR="$test_dir/runtime" DROIDLINK_TEST_ARGS="$test_dir/args"
export DROIDLINK_TEST_CAMERAS="$repo_dir/tests/camera-sizes.txt"
export DROIDLINK_ADB_ROTATION="$test_dir/rotation" DROIDLINK_HYPRCTL_LOG="$test_dir/hyprctl"
session() { bash "$repo_dir/session.sh" "$@"; }
launch_long_session() {
  session launch USB123 0 '' -- scrcpy --serial=USB123 --max-size=3840 --max-fps=60 --video-bit-rate=60M --no-audio --max-fps=120
}
# The release after a session ends is detached, so poll for the device state.
wait_for_rotation() {
  for ((attempt=0; attempt<30; attempt++)); do
    [[ "$(cat "$DROIDLINK_ADB_ROTATION")" == "$1" ]] && return 0
    sleep 0.1
  done
  echo "Rotation state is $(cat "$DROIDLINK_ADB_ROTATION" | tr '\n' ' '); expected ${1//$'\n'/ }." >&2
  return 1
}
wait_for_inactive() {
  for ((attempt=0; attempt<30; attempt++)); do
    [[ "$(session status)" == inactive ]] && return 0
    sleep 0.1
  done
  return 1
}
test -z "$(bash "$repo_dir/session.sh" check)"
if session rotate query 2>/dev/null; then
  echo 'Rotation query without a session unexpectedly succeeded.' >&2
  exit 1
fi
launch_long_session
status="$(bash "$repo_dir/session.sh" status)"
[[ "$status" == $'active\nUSB123\nmirror\n'* ]]
if bash "$repo_dir/session.sh" launch USB123 0 '' -- scrcpy --serial=USB123 2>/dev/null; then
  echo 'Duplicate launch unexpectedly succeeded.' >&2
  exit 1
fi
# The terminal is hidden by a named rule registered before it opens.
[[ "$(cat "$test_dir/hyprctl")" == $'clients -j\n''eval hl.window_rule({ name = "droidlink-terminal", match = { class = "^org\\.omarchy\\.droidlink$" }, workspace = "special:droidlink silent", no_initial_focus = true })' ]]
rg -q -- '--max-size=3840' "$test_dir/args"
rg -q -- '--video-bit-rate=60M' "$test_dir/args"

# A lock DroidLink sets is owned and released when the session stops.
for invalid in 'lock 4' 'lock' 'spin'; do
  if session rotate $invalid 2>/dev/null; then
    echo "Invalid rotate request '$invalid' unexpectedly succeeded." >&2
    exit 1
  fi
done
[[ "$(session rotate query)" == free ]]
session rotate lock 1
[[ "$(session rotate query)" == $'lock 1\nowned' ]]
[[ "$(session stop)" == 'Session stopped.' ]]
wait_for_inactive
wait_for_rotation $'1\n0'

# Auto rotate / reset drops ownership, so a later stop sends nothing.
launch_long_session
session rotate lock 3
session rotate free
[[ "$(session rotate query)" == free ]]
[[ ! -e "$XDG_RUNTIME_DIR/droidlink-$UID/rotation" ]]
session stop
wait_for_inactive

# A lock chosen on the phone is reported but survives the session.
printf '0\n2\n' > "$DROIDLINK_ADB_ROTATION"
launch_long_session
[[ "$(session rotate query)" == 'lock 2' ]]
session stop
wait_for_inactive
sleep 0.3
wait_for_rotation $'0\n2'

# A session that dies without stop (window closed, crash) is released by status.
launch_long_session
session rotate lock 0
pid="$(session status | sed -n 5p)"
kill -KILL "$pid"
wait_for_inactive
wait_for_rotation $'1\n0'

# `wait` blocks while the session runs, then ends it and releases the lock
# itself, so widgets need no status poll.
[[ "$(session path)" == "$XDG_RUNTIME_DIR/droidlink-$UID/session" ]]
[[ "$(session wait)" == inactive ]]
launch_long_session
session rotate lock 1
session wait >"$test_dir/wait.out" &
waiter=$!
sleep 0.3
kill -0 "$waiter"
kill -KILL "$(session status | sed -n 5p)"
wait "$waiter"
[[ "$(cat "$test_dir/wait.out")" == inactive ]]
[[ ! -e "$(session path)" ]]
wait_for_rotation $'1\n0'
# A scrcpy that ignores SIGTERM is killed, and the session is already gone
# when stop returns, so the next status agrees without another poll.
DROIDLINK_SCRCPY_IGNORE_TERM=1 launch_long_session
[[ "$(session stop)" == 'Session force-stopped after scrcpy did not exit cleanly.' ]]
[[ "$(session status)" == inactive ]]

# A scrcpy that exits at once still counts as started, even when a watching
# widget's status removes its session file before launch looks for it.
( for ((attempt=0; attempt<40; attempt++)); do session status >/dev/null; sleep 0.02; done ) &
watcher=$!
[[ "$(session launch USB123 0 '' -- scrcpy --serial=USB123)" == 'Session started in the hidden DroidLink terminal.' ]]
wait "$watcher"
wait_for_inactive

# A missing recording folder fails the launch with a reason instead of
# letting scrcpy die in the hidden terminal.
if error="$(session launch USB123 0 "$test_dir/missing/DroidLink.mkv" -- scrcpy --serial=USB123 2>&1)"; then
  echo 'Launch into a missing recording folder unexpectedly succeeded.' >&2
  exit 1
fi
[[ "$error" == "Recording folder $test_dir/missing does not exist."* ]]
[[ "$(session status)" == inactive ]]
if [[ $EUID -ne 0 ]]; then
  mkdir -m 500 "$test_dir/readonly"
  if error="$(session launch USB123 0 "$test_dir/readonly/DroidLink.mkv" -- scrcpy --serial=USB123 2>&1)"; then
    echo 'Launch into a read-only recording folder unexpectedly succeeded.' >&2
    exit 1
  fi
  [[ "$error" == *"is not writable"* ]]
fi
# A chosen loopback node and webcam session type survive a fresh status read.
mkdir -p "$test_dir/devices/virtual/video4linux/video12" "$test_dir/sys" "$test_dir/dev"
cat > "$test_dir/bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ "${DROIDLINK_TEST_PACKAGE:-0}" == 1 ]]
EOF
cat > "$test_dir/bin/modinfo" <<'EOF'
#!/usr/bin/env bash
[[ "${DROIDLINK_TEST_MODULE:-0}" == 1 ]]
EOF
chmod +x "$test_dir/bin/pacman" "$test_dir/bin/modinfo"
export DROIDLINK_VIDEO_SYSFS="$test_dir/sys" DROIDLINK_VIDEO_DEV="$test_dir/dev" DROIDLINK_VIDEO_MODULE_SYSFS="$test_dir/module"
[[ "$(bash "$repo_dir/webcam-devices.sh" list 2>&1)" == missing-package ]]
[[ "$(DROIDLINK_TEST_PACKAGE=1 bash "$repo_dir/webcam-devices.sh" list 2>&1)" == module-unavailable ]]
[[ "$(DROIDLINK_TEST_PACKAGE=1 DROIDLINK_TEST_MODULE=1 bash "$repo_dir/webcam-devices.sh" list 2>&1)" == module-not-loaded ]]
mkdir "$test_dir/module"
[[ "$(DROIDLINK_TEST_PACKAGE=1 DROIDLINK_TEST_MODULE=1 bash "$repo_dir/webcam-devices.sh" list 2>&1)" == no-output ]]
# A module from another package (a -git build) is not a missing package.
[[ "$(DROIDLINK_TEST_MODULE=1 bash "$repo_dir/webcam-devices.sh" list 2>&1)" == no-output ]]
rmdir "$test_dir/module"
[[ "$(DROIDLINK_TEST_MODULE=1 bash "$repo_dir/webcam-devices.sh" list 2>&1)" == module-not-loaded ]]
mkdir "$test_dir/module"
printf 'DroidLink camera\n' > "$test_dir/devices/virtual/video4linux/video12/name"
touch "$test_dir/devices/virtual/video4linux/video12/max_openers" "$test_dir/dev/video12"
ln -s "$test_dir/devices/virtual/video4linux/video12" "$test_dir/sys/video12"
[[ "$(bash "$repo_dir/webcam-devices.sh" list)" == /dev/video12$'\tDroidLink camera' ]]
if error="$(session launch USB123 webcam '' -- scrcpy --serial=USB123 --video-source=camera --no-window --v4l2-sink=/dev/video11 2>&1)"; then
  echo 'Missing V4L2 output unexpectedly succeeded.' >&2; exit 1
fi
[[ "$error" == *'No v4l2loopback output'* ]]
if error="$(DROIDLINK_TEST_SDK=30 session launch USB123 webcam '' -- scrcpy --serial=USB123 --video-source=camera --no-window --v4l2-sink=/dev/video12 2>&1)"; then
  echo 'Android 11 camera unexpectedly succeeded.' >&2; exit 1
fi
[[ "$error" == *'requires Android 12+'* ]]
session launch USB123 webcam '' -- scrcpy --serial=USB123 --video-source=camera --no-window --max-fps=120 --v4l2-sink=/dev/video12
# An output another app holds blocks a new webcam, but not an Apply restart,
# where a call reading it bridges the gap.
mkdir -p "$test_dir/busy-bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_dir/busy-bin/fuser"
chmod +x "$test_dir/busy-bin/fuser"
if error="$(PATH="$test_dir/busy-bin:$PATH" bash "$repo_dir/webcam-devices.sh" check /dev/video12 2>&1)"; then
  echo 'An occupied output was accepted.' >&2; exit 1
fi
[[ "$error" == *'is occupied'* ]]
PATH="$test_dir/busy-bin:$PATH" DROIDLINK_KEEP_READERS=1 bash "$repo_dir/webcam-devices.sh" check /dev/video12
# The preview refuses an output whose readers get another size than scrcpy
# writes, and otherwise runs ffmpeg tied to the shell's lifetime.
mkdir -p "$test_dir/preview-bin"
printf '#!/usr/bin/env bash\necho "${DROIDLINK_TEST_PROBE:?}"\n' > "$test_dir/preview-bin/ffprobe"
printf '#!/usr/bin/env bash\n[[ "$1 $2" == "--pdeathsig TERM" ]] || exit 9\nshift 2\nexec "$@"\n' > "$test_dir/preview-bin/setpriv"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$DROIDLINK_TEST_FFMPEG"\n' > "$test_dir/preview-bin/ffmpeg"
chmod +x "$test_dir/preview-bin/"*
printf 'YU12:1080x1920@30\n' > "$test_dir/devices/virtual/video4linux/video12/format"
preview() { PATH="$test_dir/preview-bin:$PATH" DROIDLINK_TEST_FFMPEG="$test_dir/ffmpeg-args" bash "$repo_dir/webcam-preview.sh" "$@"; }
frame="$XDG_RUNTIME_DIR/droidlink-$UID/preview-abc123.jpg"
if error="$(DROIDLINK_TEST_PROBE=2032x1144 preview /dev/video12 "$frame" 2>&1)"; then
  echo 'A garbled output was previewed.' >&2; exit 1
fi
[[ "$error" == *'get 2032x1144 while scrcpy writes 1080x1920'* ]]
[[ ! -e "$test_dir/ffmpeg-args" ]]
DROIDLINK_TEST_PROBE=1080x1920 preview /dev/video12 "$frame"
grep -qx -- '/dev/video12' "$test_dir/ffmpeg-args"
grep -qx -- "$frame" "$test_dir/ffmpeg-args"
grep -qx -- '-atomic_writing' "$test_dir/ffmpeg-args"
for bad in '/tmp/preview-abc.jpg' "$XDG_RUNTIME_DIR/droidlink-$UID/preview-../x.jpg"; do
  if DROIDLINK_TEST_PROBE=1080x1920 preview /dev/video12 "$bad" 2>/dev/null; then
    echo "Preview accepted the path $bad." >&2; exit 1
  fi
done
if DROIDLINK_TEST_PROBE=1080x1920 preview '/dev/video12;x' "$frame" 2>/dev/null; then
  echo 'Preview accepted a bad device.' >&2; exit 1
fi
# The camera list comes from the phone through scrcpy, even mid-session.
[[ "$(bash "$repo_dir/webcam-devices.sh" cameras USB123)" == *'--camera-id=2    (front, 4000x3000'* ]]
if bash "$repo_dir/webcam-devices.sh" cameras --help >/dev/null 2>&1; then
  echo 'An option as the camera serial was accepted.' >&2; exit 1
fi
# The webcam's sink travels in the session state for every widget's preview.
[[ "$(session status)" == $'active\nUSB123\nwebcam\n/dev/video12\n'* ]]
session stop
wait_for_inactive
DROIDLINK_FOOT="$test_dir/mock-foot" DROIDLINK_FOOT_LOG="$test_dir/foot" session launch USB123 mirror '' -- scrcpy --serial=USB123 --max-fps=120
[[ "$(cat "$test_dir/foot")" == 'foot:--app-id=org.omarchy.droidlink --title=DroidLink --hold -- bash '*'/session.sh run '*'/request.'* ]]
[[ "$(session status)" == $'active\nUSB123\nmirror\n'* ]]
session stop
wait_for_inactive
# A real camera error is found even in a log longer than a pipe buffer.
rm -f -- "$XDG_RUNTIME_DIR/droidlink-$UID/stopped"
{ echo 'ERROR: Camera 5 not found'; seq 200000; } > "$XDG_RUNTIME_DIR/droidlink-$UID/scrcpy.log"
[[ "$(session status)" == $'inactive\nThe selected camera is unavailable.'* ]]
: > "$XDG_RUNTIME_DIR/droidlink-$UID/stopped"
# Shutdown warnings after a user stop are not reported as a camera failure.
printf '[server] WARN: Camera capture failed: frame 3767\n' > "$XDG_RUNTIME_DIR/droidlink-$UID/scrcpy.log"
[[ "$(session status)" == inactive ]]
# A session that ended by itself reports the cause; a dropped frame is not one.
rm -f -- "$XDG_RUNTIME_DIR/droidlink-$UID/stopped"
[[ "$(session status)" == inactive ]]
printf 'ERROR: camera size 1920x1080 is not supported\n' > "$XDG_RUNTIME_DIR/droidlink-$UID/scrcpy.log"
[[ "$(session status)" == $'inactive\nThis camera does not support the chosen size. Select Automatic or another quality and check Show log.' ]]
# A launch already starting blocks a second one, which must not close the
# first one's terminal as stale.
sleep 30 &
starting=$!
printf '%s\n%s\n' "$starting" "$(XDG_RUNTIME_DIR="$test_dir/runtime" bash -c 'source "$1/proc-lib.sh"; start_time "$2"' _ "$repo_dir" "$starting")" > "$XDG_RUNTIME_DIR/droidlink-$UID/launching"
if error="$(session launch USB123 mirror '' -- scrcpy --serial=USB123 2>&1)"; then
  echo 'A second launch unexpectedly succeeded.' >&2; exit 1
fi
[[ "$error" == *'already starting'* ]]
kill "$starting"
wait "$starting" 2>/dev/null || true
# Leftover terminals close at launch, but never a process that also owns a
# window of another app (a single-instance terminal).
sleep 30 &
stale=$!
sleep 30 &
shared=$!
printf '[{"pid":%d,"class":"org.omarchy.droidlink"},{"pid":%d,"class":"org.omarchy.droidlink"},{"pid":%d,"class":"com.mitchellh.ghostty"}]\n' "$stale" "$shared" "$shared" > "$test_dir/clients.json"
DROIDLINK_HYPRCTL_CLIENTS="$test_dir/clients.json" session launch USB123 mirror '' -- scrcpy --serial=USB123 --max-fps=120
wait "$stale" 2>/dev/null || true
! kill -0 "$stale" 2>/dev/null
kill -0 "$shared"
kill "$shared"
wait "$shared" 2>/dev/null || true
session stop
wait_for_inactive
echo 'DROIDLINK_SESSION_OK'
