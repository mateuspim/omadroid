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

echo OMADROID_APK_LABEL_OK
