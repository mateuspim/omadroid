#!/usr/bin/env bash
# send-text.sh against a fake adb that evaluates the typed command like the
# device's sh. Nothing here touches a real device.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-text.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-text.* ]] && rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/device"
cp "$repo_dir/tests/mock-adb.sh" "$test_dir/bin/adb"
chmod +x "$test_dir/bin/adb"
export PATH="$test_dir/bin:$PATH" OMADROID_TEXT_DIR="$test_dir/device"
device="$test_dir/device"
fail() {
  echo "OMADROID_TEXT_FAILED: $*" >&2
  exit 1
}
# send EXPECTED_CODE ARGS... → output in $out, what was typed in $typed.
send() {
  local expected="$1" code=0
  shift
  rm -f "$device/"*
  out="$(bash "$repo_dir/scripts/send-text.sh" "$@" 2>&1)" || code=$?
  typed="$(cat "$device/typed" 2>/dev/null || true)"
  [[ "$code" == "$expected" ]] || fail "send-text $* exited $code; expected $expected: $out"
}

# Every character the device's sh treats specially is typed as is.
for text in 'hello world' "it's" '"quoted"' 'cost $HOME' 'back`tick`' 'a\b' 'one & two; three' '*.txt | (x)' '  spaced  ' '~!@#%^=+[]{}<>?,./' '&& rm -rf x'; do
  send 0 USB123 "text:$text"
  [[ "$typed" == "$text" ]] || fail "typed '$typed' for '$text'"
done

# Keys and text run in order, in one adb shell call.
send 0 USB123 key:ctrl+a key:backspace 'text:new text' key:tab key:enter
[[ "$typed" == '<CTRL+A><DEL>new text<TAB><ENTER>' ]] || fail "sequence: $typed"
[[ "$(wc -l <"$device/argv")" == 1 ]] || fail "one adb shell: $(cat "$device/argv")"
send 0 USB123 key:ctrl+shift+z key:f5 key:7 key:del key:home key:back
[[ "$typed" == '<CTRL+SHIFT+Z><F5><7><FORWARD_DEL><MOVE_HOME><BACK>' ]] || fail "key names: $typed"

# A dash works like a plus.
send 0 USB123 key:ctrl-a key:ctrl-shift-z
[[ "$typed" == '<CTRL+A><CTRL+SHIFT+Z>' ]] || fail "dash separator: $typed"

# Known limit: Android types a literal %s as a space.
send 0 USB123 'text:100%sure'
[[ "$typed" == '100 ure' ]] || fail "literal %s: $typed"

# Every step is checked before anything is sent.
send 2 USB123 text:ok 'text:café'
[[ "$out" == *"only printable ASCII"* && ! -e "$device/argv" ]] || fail "non-ASCII refused: $out"
send 2 USB123 $'text:two\nlines'
send 2 USB123 text:ok key:hyper
[[ "$out" == *"Unknown key '{hyper}'"* && ! -e "$device/argv" ]] || fail "unknown key: $out"
send 2 USB123 key:super+a
[[ "$out" == *"Unknown modifier 'super'"* ]] || fail "unknown modifier: $out"
for bad in key: key:ctrl+ key:ctrl- key:+ key:- key:f13 'key:$(id)'; do
  send 2 USB123 "$bad"
  [[ ! -e "$device/argv" ]] || fail "'$bad' refused"
done
send 2 USB123 text:
send 1 USB123
[[ "$out" == *"Nothing to send"* ]] || fail "no steps: $out"
send 1 USB123 hello
[[ "$out" == *"Unexpected step 'hello'"* ]] || fail "bare text: $out"
send 1 'bad serial' text:hi
[[ ! -e "$device/argv" ]] || fail "bad serial refused"

# adb errors are reported with adb's own text.
OMADROID_TEST_CASE=input_error send 1 USB123 text:hi
[[ "$out" == *"Couldn't type on USB123: java.lang.IllegalStateException"* ]] || fail "input exception: $out"
send 1 MISSING text:hi
[[ "$out" == *"Couldn't type on MISSING"* ]] || fail "adb failure: $out"
echo OMADROID_TEXT_OK
