#!/usr/bin/env bash
# audio-codes.py against fixture dex files: the Tab S11's codes, a phone
# without Samsung's app volume, and tables it must refuse.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-codes.XXXXXX)"
trap '[[ "$test_dir" == /tmp/droidlink-codes.* ]] && rm -rf -- "$test_dir"' EXIT
fail() {
  echo "DROIDLINK_CODES_FAILED: $*" >&2
  exit 1
}
codes() {
  python3 -I "$repo_dir/tests/make-audio-dex.py" "$test_dir/$1.jar" "$1"
  python3 -I "$repo_dir/audio-codes.py" "$test_dir/$1.jar"
}
refused() {
  local output code=0
  output="$(codes "$1" 2>&1)" || code=$?
  [[ "$code" == 2 && "$output" == *"$2"* ]] || fail "$1 not refused with '$2': exit $code, $output"
}

expected=$'getAppVolume=294\ngetStreamVolume=27\nisAppMute=296\nisMasterMute=25\nsetAppMute=295\nsetAppVolume=293\nsetMasterMute=26'
[[ "$(codes samsung)" == "$expected" ]] || fail "samsung codes: $(codes samsung)"
# A boolean and a null carry no payload bytes; misreading them shifted every code.
[[ "$(codes shifted)" == "$expected" ]] || fail "codes after payload-free statics: $(codes shifted)"
[[ "$(codes plain)" == $'getStreamVolume=27\nisMasterMute=25\nsetMasterMute=26' ]] || fail "plain phone codes: $(codes plain)"
# An overloaded method could be called with the wrong arguments, so it's left out.
[[ "$(codes overload)" != *setAppVolume* ]] || fail "overloaded setAppVolume kept"
refused gap "aren't exactly 1..300"
printf 'not a jar' >"$test_dir/broken.jar"
code=0
python3 -I "$repo_dir/audio-codes.py" "$test_dir/broken.jar" >/dev/null 2>&1 || code=$?
[[ "$code" == 2 ]] || fail "broken jar exited $code"

echo DROIDLINK_CODES_OK
