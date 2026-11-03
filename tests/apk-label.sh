#!/usr/bin/env bash
# apk-label.py against fixture APKs (tests/make-apk.py): literal and resource
# labels, the locale it prefers, every entry-table layout, and APKs it refuses.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/omadroid-apk.XXXXXX)"
trap '[[ "$test_dir" == /tmp/omadroid-apk.* ]] && rm -rf -- "$test_dir"' EXIT
fail() {
  echo "OMADROID_APK_LABEL_FAILED: $*" >&2
  exit 1
}
label() {
  python3 -I "$repo_dir/tests/make-apk.py" "$test_dir/$1.apk" "$1"
  python3 -I "$repo_dir/scripts/apk-label.py" "$test_dir/$1.apk"
}
expect() {
  local got
  got="$(label "$1")" || fail "$1 exited non-zero"
  [[ "$got" == "$2" ]] || fail "$1 label: '$got'; expected '$2'"
}
refused() {
  local output code=0
  output="$(python3 -I "$repo_dir/scripts/apk-label.py" "$1" 2>&1)" || code=$?
  [[ "$code" == 1 && "$output" == *"$2"* ]] || fail "$1 not refused with '$2': exit $code, $output"
}

expect literal 'Plain Notes'
# The default locale wins even when another config comes first.
expect default 'Example Keys'
expect english 'Example Keys (en)'
expect offset16 'Example Keys'
expect sparse 'Example Keys'
expect compact 'Example Keys'
expect chained 'Example Keys'
python3 -I "$repo_dir/tests/make-apk.py" "$test_dir/nolabel.apk" nolabel
refused "$test_dir/nolabel.apk" 'no android:label'
printf 'not an apk' >"$test_dir/broken.apk"
refused "$test_dir/broken.apk" 'broken.apk'
refused "$test_dir/missing.apk" 'missing.apk'

# Hostile APKs (omacom/omarchy-plugin-marketplace#13776): each cap fails
# closed with a plain reason, fast, before memory grows past it.
hostile() {
  local started=$SECONDS
  python3 -I "$repo_dir/tests/make-apk.py" "$test_dir/$1.apk" "$1"
  refused "$test_dir/$1.apk" "$2"
  ((SECONDS - started < 10)) || fail "$1 took $((SECONDS - started)) s"
}
hostile bomb 'AndroidManifest.xml declares 9437184 bytes; expected at most 8388608'
# zipfile stops at the declared 100 bytes; the CRC no longer matches.
hostile liar 'Bad CRC-32'
hostile aggregate 'resources.arsc declares'
hostile members 'declares 60001 members; expected at most 60000'
hostile zip64 'ZIP64'
hostile bigdir 'central directory has 9437184 bytes'
hostile hugepool 'lists 268435456 strings'
truncate -s $((300 * 1024 * 1024 + 1)) "$test_dir/huge.apk"
refused "$test_dir/huge.apk" 'has 314572801 bytes; expected at most 314572800'
# The parser runs under address-space and CPU caps.
limits="$(python3 -I -c 'import runpy, sys; m = runpy.run_path(sys.argv[1]); m["limit_resources"](); print(open("/proc/self/limits").read())' "$repo_dir/scripts/apk-label.py")"
grep -Eq '^Max address space +536870912 ' <<<"$limits" || fail "no address-space cap: $limits"
grep -Eq '^Max cpu time +20 ' <<<"$limits" || fail "no CPU cap: $limits"

echo OMADROID_APK_LABEL_OK
