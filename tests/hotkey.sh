#!/usr/bin/env bash
# hotkey.sh against a scratch bindings.lua and a fake `omarchy` that lists the
# bound keys. The real Hyprland config is never read or written.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/droidlink-hotkey.XXXXXX)"
trap '[[ "$test_dir" == /tmp/droidlink-hotkey.* ]] && rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/hypr"
cp "$repo_dir/tests/mock-omarchy.sh" "$test_dir/bin/omarchy"
printf '#!/usr/bin/env bash\necho reload >>"%s/reloads"\n' "$test_dir" >"$test_dir/bin/hyprctl"
chmod +x "$test_dir/bin/"*
bindings="$test_dir/hypr/bindings.lua"
export PATH="$test_dir/bin:$PATH" DROIDLINK_HYPR_BINDINGS="$bindings"
fail() {
  echo "DROIDLINK_HOTKEY_FAILED: $*" >&2
  exit 1
}
# hotkey EXPECTED_CODE ARGS... → output in $out.
hotkey() {
  local expected="$1" code=0
  shift
  out="$(bash "$repo_dir/hotkey.sh" "$@" 2>&1)" || code=$?
  [[ "$code" == "$expected" ]] || fail "hotkey $* exited $code; expected $expected: $out"
}
user_lines=$'-- my binds\no.bind("SUPER + SHIFT + G", "ZapFast", { launch = "zapfast" })'
printf '%s\n' "$user_lines" >"$bindings"

hotkey 0 status
[[ "$out" == none ]] || fail "nothing installed yet: $out"

# Installing appends one block and leaves the user's lines alone.
hotkey 0 set 'super+alt+d'
[[ "$out" == 'installed SUPER + ALT + D' ]] || fail "set output: $out"
[[ "$(head -2 "$bindings")" == "$user_lines" ]] || fail "user lines kept: $(cat "$bindings")"
grep -qx 'o.bind("SUPER + ALT + D", "DroidLink send text", "omarchy-shell shell toggle pym.droidlink")' "$bindings" || fail "bind line: $(cat "$bindings")"
ls "$test_dir/hypr/" | grep -q '^bindings.lua.bak.' || fail "backup kept"
[[ -s "$test_dir/reloads" ]] || fail "Hyprland reloaded"
hotkey 0 status
[[ "$out" == 'installed SUPER + ALT + D' ]] || fail "status after set: $out"

# Changing it replaces DroidLink's block; its own bind is no conflict.
hotkey 0 set 'ALT + SUPER + D'
hotkey 0 set 'SUPER + CTRL + Y'
[[ "$(grep -c 'DroidLink send text' "$bindings")" == 3 ]] || fail "one block (2 markers + bind): $(cat "$bindings")"
grep -q 'SUPER + CTRL + Y' "$bindings" && ! grep -q 'SUPER + ALT + D' "$bindings" || fail "combo replaced: $(cat "$bindings")"

# An unchanged combination doesn't rewrite the file or reload.
rm -f "$test_dir/reloads"
hotkey 0 set 'super + ctrl + y'
[[ ! -e "$test_dir/reloads" ]] || fail "no reload when unchanged"

# Taken combinations, in any modifier order, are refused by name.
hotkey 2 set 'CTRL + SUPER + A'
[[ "$out" == 'SUPER + CTRL + A is already bound to Audio. Pick another combination.' ]] || fail "conflict: $out"
hotkey 2 set 'SUPER + ALT + SHIFT + B'
[[ "$out" == *'Browser'* ]] || fail "conflict with Omarchy's order: $out"
hotkey 2 set 'SUPER + SHIFT + G'
[[ "$out" == *'ZapFast'* ]] || fail "conflict with a user bind: $out"
grep -q 'SUPER + CTRL + Y' "$bindings" || fail "a refused combo leaves the bind"

# Malformed combinations.
for bad in 'D' 'SUPER +' 'SUPER + A + B' 'SUPER + $(id)' 'SUPER + "x"' 'SUPER + *'; do
  hotkey 1 set "$bad"
  [[ "$out" == *'expected'* ]] || fail "malformed '$bad': $out"
done
hotkey 1 frobnicate

# Removing deletes only the block.
hotkey 0 remove
[[ "$out" == none && "$(cat "$bindings")" == "$user_lines" ]] || fail "removed: $(cat "$bindings")"
hotkey 0 remove

# A symlinked bindings.lua (dotfiles) stays a symlink.
mv "$bindings" "$test_dir/hypr/real.lua"
ln -s real.lua "$bindings"
hotkey 0 set 'SUPER + ALT + D'
[[ -L "$bindings" ]] && grep -q 'SUPER + ALT + D' "$test_dir/hypr/real.lua" || fail "symlink kept"
echo DROIDLINK_HOTKEY_OK
