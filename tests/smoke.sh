#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-smoke.XXXXXX)"
trap '[[ "$test_dir" == /tmp/droidlink-smoke.* ]] && rm -rf -- "$test_dir"' EXIT
if [[ -n "${DROIDLINK_PREVIEW_DIR:-}" ]]; then
  cp "$repo_dir/tests/Preview.qml" "$test_dir/shell.qml"
else
  cp "$repo_dir/tests/Smoke.qml" "$test_dir/shell.qml"
fi
mkdir "$test_dir/bin" "$test_dir/config" "$test_dir/runtime" "$test_dir/state" "$test_dir/keyring" "$test_dir/device" "$test_dir/home"
mkdir -p "$test_dir/devices/virtual/video4linux/video12" "$test_dir/sys" "$test_dir/dev"
printf 'DroidLink test camera\n' > "$test_dir/devices/virtual/video4linux/video12/name"
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
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
ln -s "$repo_dir" "$test_dir/plugin"
test_status=0
if [[ -n "${DROIDLINK_PREVIEW_DIR:-}" ]]; then
  platform=wayland
else
  unset DISPLAY WAYLAND_DISPLAY
  platform=offscreen
fi
DROIDLINK_TEST_CAMERAS="$repo_dir/tests/camera-sizes.txt" DROIDLINK_FOOT="$test_dir/bin/foot" HOME="$test_dir/home" DROIDLINK_CLIPBOARD_LOG="$test_dir/clipboard" DROIDLINK_VIDEO_SYSFS="$test_dir/sys" DROIDLINK_VIDEO_DEV="$test_dir/dev" DROIDLINK_POWER_DIR="$test_dir/device" DROIDLINK_KEYRING="$test_dir/keyring" XDG_STATE_HOME="$test_dir/state" DROIDLINK_HYPRCTL_LOG="$test_dir/hyprctl" PATH="$test_dir/bin:$PATH" XDG_CONFIG_HOME="$test_dir/config" XDG_RUNTIME_DIR="$test_dir/runtime" DROIDLINK_TEST_ARGS="$test_dir/scrcpy-args" QT_QPA_PLATFORM="$platform" QT_QPA_PLATFORMTHEME=xdgdesktopportal QT_STYLE_OVERRIDE=Fusion timeout 20s quickshell -p "$test_dir/shell.qml" --no-color >"$test_dir/output" 2>&1 || test_status=$?
cat "$test_dir/output"
test "$test_status" -eq 0
if rg -i '(TypeError|ReferenceError|SyntaxError|is not a type|Cannot assign|Unable to assign|Binding loop|Failed to load configuration|DROIDLINK_TEST_FAILED)' "$test_dir/output"; then exit 1; fi
if [[ -n "${DROIDLINK_PREVIEW_DIR:-}" ]]; then
  rg -q DROIDLINK_PREVIEW_OK "$test_dir/output"
  exit 0
fi
rg -q DROIDLINK_SMOKE_OK "$test_dir/output"
rg -q -- '--no-audio' "$test_dir/scrcpy-args"
rg -q -- '--turn-screen-off' "$test_dir/scrcpy-args"
rg -q -- '--fullscreen' "$test_dir/scrcpy-args"
rg -q -- '--record=.*/DroidLink-USB123-.*\.mkv' "$test_dir/scrcpy-args"
rg -q -- '--video-source=camera' "$test_dir/scrcpy-args"
rg -q -- '--v4l2-sink=/dev/video12' "$test_dir/scrcpy-args"
rg -q '^omarchy pkg add v4l2loopback-dkms$' "$test_dir/clipboard"
rg -q 'Fixture profile' "$test_dir/config/omarchy/droidlink.ini"
rg -q 'webcamJson=.*camera.*id:1' "$test_dir/config/omarchy/droidlink.ini"
# "Wake on mirror launch" is on by default.
test -e "$test_dir/device/awake"
