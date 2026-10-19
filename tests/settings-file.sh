#!/usr/bin/env bash
# settings-file.sh keeps omadroid.ini owner-only without touching its content.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-settings.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-settings.* ]] && rm -rf -- "$test_dir"' EXIT
fail() {
  echo "OMADROID_SETTINGS_FAILED: $*" >&2
  exit 1
}
file="$test_dir/config/omarchy/omadroid.ini"

# Missing: created empty and owner-only, with its folder.
(umask 022; bash "$repo_dir/scripts/settings-file.sh" "$file")
[[ -f "$file" && ! -s "$file" && "$(stat -c %a "$file")" == 600 ]] || fail "new file: $(stat -c %a "$file" 2>&1)"

# An older readable file is tightened and keeps its settings.
printf '[preferences]\nlastTextTarget=USB123\n' >"$file"
chmod 644 "$file"
bash "$repo_dir/scripts/settings-file.sh" "$file"
[[ "$(stat -c %a "$file")" == 600 && "$(cat "$file")" == $'[preferences]\nlastTextTarget=USB123' ]] || fail "existing file: $(stat -c %a "$file") $(cat "$file")"
echo OMADROID_SETTINGS_OK
