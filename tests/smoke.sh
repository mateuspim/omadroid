#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-smoke.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-smoke.* ]] && rm -rf -- "$test_dir"' EXIT
if [[ -n "${OMADROID_PREVIEW_DIR:-}" ]]; then
  # OMADROID_PREVIEW_QML swaps in another capture script (e.g. one component).
  cp "${OMADROID_PREVIEW_QML:-$repo_dir/tests/Preview.qml}" "$test_dir/shell.qml"
else
  cp "$repo_dir/tests/Smoke.qml" "$test_dir/shell.qml"
fi
mkdir "$test_dir/bin" "$test_dir/text" "$test_dir/config" "$test_dir/runtime" "$test_dir/state" "$test_dir/keyring" "$test_dir/device" "$test_dir/home"
mkdir -p "$test_dir/devices/virtual/video4linux/video12" "$test_dir/sys" "$test_dir/dev"
printf 'OmaDroid test camera\n' > "$test_dir/devices/virtual/video4linux/video12/name"
touch "$test_dir/devices/virtual/video4linux/video12/keep_format" "$test_dir/dev/video12"
ln -s "$test_dir/devices/virtual/video4linux/video12" "$test_dir/sys/video12"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
cp "$repo_dir/tests/mock-scrcpy.sh" "$test_dir/bin/scrcpy"
cp "$repo_dir/tests/mock-omarchy.sh" "$test_dir/bin/omarchy"
cp "$repo_dir/tests/mock-xdg-terminal-exec.sh" "$test_dir/bin/xdg-terminal-exec"
cp "$repo_dir/tests/mock-avahi-browse.sh" "$test_dir/bin/avahi-browse"
cp "$repo_dir/tests/mock-hyprctl.sh" "$test_dir/bin/hyprctl"
cp "$repo_dir/tests/mock-secret-tool.sh" "$test_dir/bin/secret-tool"
cp "$repo_dir/tests/mock-qrencode.sh" "$test_dir/bin/qrencode"
cp "$repo_dir/tests/mock-wl-copy.sh" "$test_dir/bin/wl-copy"
cp "$repo_dir/tests/mock-foot.sh" "$test_dir/bin/foot"
chmod +x "$test_dir/bin/adb" "$test_dir/bin/scrcpy" "$test_dir/bin/omarchy" "$test_dir/bin/xdg-terminal-exec" "$test_dir/bin/avahi-browse" "$test_dir/bin/hyprctl" "$test_dir/bin/secret-tool" "$test_dir/bin/qrencode" "$test_dir/bin/wl-copy" "$test_dir/bin/foot"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
if [[ -n "${OMADROID_PREVIEW_DIR:-}" ]]; then
  # Previews render offscreen, where KeyboardPanel's PanelWindow can't load.
  mkdir "$test_dir/Ui"
  ln -s /usr/share/omarchy/shell/Ui/* "$test_dir/Ui/"
  ln -sf "$repo_dir/tests/offscreen-ui/KeyboardPanel.qml" "$test_dir/Ui/KeyboardPanel.qml"
else
  ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
fi
ln -s "$repo_dir" "$test_dir/plugin"
# The Sound section's device: tests/mock-volume-adb.sh with the Tab S11's codes.
mkdir "$test_dir/volume"
python3 -I "$repo_dir/tests/make-audio-dex.py" "$test_dir/volume/framework.jar"
printf 13 >"$test_dir/volume/stream-3"
printf 10 >"$test_dir/volume/app-10360"
printf '10360 started\n' >"$test_dir/volume/players"
# An omadroid.ini left readable by an older version.
mkdir -p "$test_dir/config/omarchy"
: >"$test_dir/config/omarchy/omadroid.ini"
chmod 644 "$test_dir/config/omarchy/omadroid.ini"
test_status=0
unset DISPLAY WAYLAND_DISPLAY
platform=offscreen
# Previews wait for discovery before each capture, so they run longer.
run_limit=20s
[[ -n "${OMADROID_PREVIEW_DIR:-}" ]] && run_limit=60s
OMADROID_VOLUME_MOCK="$repo_dir/tests/mock-volume-adb.sh" OMADROID_VOLUME_DIR="$test_dir/volume" XDG_CACHE_HOME="$test_dir/cache" OMADROID_TEST_CAMERAS="$repo_dir/tests/camera-sizes.txt" OMADROID_FOOT="$test_dir/bin/foot" HOME="$test_dir/home" OMADROID_CLIPBOARD_LOG="$test_dir/clipboard" OMADROID_VIDEO_SYSFS="$test_dir/sys" OMADROID_VIDEO_DEV="$test_dir/dev" OMADROID_POWER_DIR="$test_dir/device" OMADROID_TEXT_DIR="$test_dir/text" OMADROID_HYPR_BINDINGS="$test_dir/bindings.lua" OMADROID_KEYRING="$test_dir/keyring" XDG_STATE_HOME="$test_dir/state" OMADROID_HYPRCTL_LOG="$test_dir/hyprctl" PATH="$test_dir/bin:$PATH" XDG_CONFIG_HOME="$test_dir/config" XDG_RUNTIME_DIR="$test_dir/runtime" OMADROID_TEST_ARGS="$test_dir/scrcpy-args" QT_QPA_PLATFORM="$platform" QT_QPA_PLATFORMTHEME=xdgdesktopportal QT_STYLE_OVERRIDE=Fusion timeout "$run_limit" quickshell -p "$test_dir/shell.qml" --no-color >"$test_dir/output" 2>&1 || test_status=$?
cat "$test_dir/output"
test "$test_status" -eq 0
if rg -i '(TypeError|ReferenceError|SyntaxError|is not a type|Cannot assign|Unable to assign|Binding loop|Failed to load configuration|OMADROID_TEST_FAILED)' "$test_dir/output"; then exit 1; fi
if [[ -n "${OMADROID_PREVIEW_DIR:-}" ]]; then
  rg -q OMADROID_PREVIEW_OK "$test_dir/output"
  exit 0
fi
rg -q OMADROID_SMOKE_OK "$test_dir/output"
rg -q -- '--no-audio' "$test_dir/scrcpy-args"
rg -q -- '--turn-screen-off' "$test_dir/scrcpy-args"
rg -q -- '--fullscreen' "$test_dir/scrcpy-args"
rg -q -- '--record=.*/OmaDroid-USB123-.*\.mkv' "$test_dir/scrcpy-args"
rg -q -- '--video-source=camera' "$test_dir/scrcpy-args"
rg -q -- '--v4l2-sink=/dev/video12' "$test_dir/scrcpy-args"
rg -q '^omarchy pkg add v4l2loopback-dkms$' "$test_dir/clipboard"
rg -q 'Fixture profile' "$test_dir/config/omarchy/omadroid.ini"
rg -q 'webcamJson=.*camera.*id:1' "$test_dir/config/omarchy/omadroid.ini"
# Send text pressed the recorded keys, typed on the chosen phone and pressed Enter.
[[ "$(cat "$test_dir/text/typed")" == "<CTRL+A><DEL>it's {ok}<ENTER>" ]]
# The text went to adb on stdin, never in its arguments.
! rg -q 'ok' "$test_dir/text/argv"
rg -q 'lastTextTarget=adb-PHONE-random' "$test_dir/config/omarchy/omadroid.ini"
# It was tightened at startup and Qt's saves after that kept it owner-only.
[[ "$(stat -c %a "$test_dir/config/omarchy/omadroid.ini")" == 600 ]]
# The Settings page installed the Send text hotkey.
rg -qxF 'o.bind("SUPER + ALT + D", "OmaDroid send text", "omarchy-shell shell toggle pym.omadroid")' "$test_dir/bindings.lua"
# The Sound section sent only the drag's last value.
[[ "$(cat "$test_dir/volume/app-10360")" == 40 ]]
# Mute all muted rather than unmuted.
[[ "$(cat "$test_dir/volume/master")" == 1 ]]
! grep -q 'unexpected' "$test_dir/volume/log"
# "Wake on mirror launch" is on by default; the card's Lock ran after it.
rg -qxF 'input keyevent KEYCODE_WAKEUP' "$test_dir/device/argv"
rg -qxF 'input keyevent KEYCODE_SLEEP' "$test_dir/device/argv"
test -e "$test_dir/device/locked"
