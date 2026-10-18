#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-webcam-setup.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-webcam-setup.* ]] && rm -rf -- "$test_dir"' EXIT
mkdir "$test_dir/bin"
cp "$repo_dir/tests/mock-xdg-terminal-exec.sh" "$test_dir/bin/xdg-terminal-exec"
cat > "$test_dir/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
printf 'omarchy:%s\n' "$*" >> "$OMADROID_SETUP_LOG"
EOF
cat > "$test_dir/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo:%s\n' "$*" >> "$OMADROID_SETUP_LOG"
[[ "$1" != tee ]] || exec "$@"
EOF
chmod +x "$test_dir/bin/omarchy" "$test_dir/bin/sudo" "$test_dir/bin/xdg-terminal-exec"
cp "$repo_dir/tests/mock-foot.sh" "$test_dir/mock-foot"
chmod +x "$test_dir/mock-foot"
etc="$test_dir/etc"
mkdir -p "$etc/modules-load.d" "$etc/modprobe.d"
export PATH="$test_dir/bin:$PATH" OMADROID_SETUP_LOG="$test_dir/log" OMADROID_FOOT="$test_dir/no-foot" OMADROID_ETC="$etc"
modprobe_line='sudo:modprobe v4l2loopback devices=1 exclusive_caps=1'
persist_lines="sudo:tee $etc/modules-load.d/v4l2loopback.conf"$'\n'"sudo:tee $etc/modprobe.d/v4l2loopback.conf"
bash "$repo_dir/scripts/webcam-setup.sh" install > "$test_dir/output"
[[ "$(cat "$test_dir/log")" == "omarchy:pkg add v4l2loopback-dkms"$'\n'"$modprobe_line"$'\n'"$persist_lines" ]]
[[ "$(cat "$etc/modules-load.d/v4l2loopback.conf")" == v4l2loopback ]]
[[ "$(cat "$etc/modprobe.d/v4l2loopback.conf")" == 'options v4l2loopback devices=1 exclusive_caps=1' ]]
# Existing boot config is the user's own: load now, never overwrite it.
printf 'options v4l2loopback video_nr=10\n' > "$etc/modprobe.d/v4l2loopback.conf"
rm "$etc/modules-load.d/v4l2loopback.conf"
: > "$test_dir/log"
bash "$repo_dir/scripts/webcam-setup.sh" load > "$test_dir/output"
[[ "$(cat "$test_dir/log")" == "$modprobe_line" ]]
[[ "$(cat "$etc/modprobe.d/v4l2loopback.conf")" == 'options v4l2loopback video_nr=10' ]]
[[ ! -e "$etc/modules-load.d/v4l2loopback.conf" ]]
grep -q 'Kept your existing' "$test_dir/output"
rm "$etc/modprobe.d/v4l2loopback.conf"
: > "$test_dir/log"
bash "$repo_dir/scripts/webcam-setup.sh" open install
for ((attempt=0; attempt<20; attempt++)); do
  [[ -s "$test_dir/log" ]] && break
  sleep 0.1
done
[[ "$(cat "$test_dir/log")" == *'launch terminal --app-id=org.omarchy.terminal --title=OmaDroid webcam setup -- bash '*'/webcam-setup.sh install' ]]
: > "$test_dir/log"
OMADROID_FOOT="$test_dir/mock-foot" OMADROID_FOOT_LOG="$test_dir/log" bash "$repo_dir/scripts/webcam-setup.sh" open load
for ((attempt=0; attempt<20; attempt++)); do
  [[ "$(wc -l < "$test_dir/log")" -ge 4 ]] && break
  sleep 0.1
done
[[ "$(cat "$test_dir/log")" == "foot:--app-id=org.omarchy.terminal --title=OmaDroid webcam setup -- bash "*$'/webcam-setup.sh load\n'"$modprobe_line"$'\n'"$persist_lines" ]]
echo OMADROID_WEBCAM_SETUP_OK
