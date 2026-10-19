#!/usr/bin/env bash
# Every OmaDroid test suite in one command: the Node projections, then each
# standalone shell suite (mocks and fixture helpers are not suites). Suites
# with a variant run once more with its OMADROID_TEST_CASE. Stops at the
# first failure, naming it; prints OMADROID_ALL_OK when everything passed.
#
#   bash tests/run-all.sh
set -uo pipefail
tests_dir="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname -- "$tests_dir")"

# Each entry: "SUITE.sh" or "SUITE.sh CASE" (run with OMADROID_TEST_CASE=CASE).
shell_suites=(
  audio-codes.sh
  device-power.sh
  device-volume.sh
  go-wireless.sh
  hotkey.sh
  send-text.sh
  session.sh
  settings-file.sh
  webcam-setup.sh
  shared-discovery.sh
  'shared-discovery.sh no_track'
  smoke.sh
  'smoke.sh avahi_unavailable'
)

# Names the failed step on stderr and exits with its code.
stop_on_failure() {
  local code="$1" name="$2"
  ((code == 0)) && return 0
  echo "OMADROID_ALL_FAILED: $name exited $code" >&2
  exit "$code"
}

run_suite() {
  local suite="$1" test_case="${2:-}" code=0
  echo "== $suite${test_case:+ (OMADROID_TEST_CASE=$test_case)}"
  if [[ -n "$test_case" ]]; then
    OMADROID_TEST_CASE="$test_case" bash "$tests_dir/$suite" || code=$?
  else
    (unset OMADROID_TEST_CASE; bash "$tests_dir/$suite") || code=$?
  fi
  stop_on_failure "$code" "$suite${test_case:+ $test_case}"
}

# A new suite left out of the list above would otherwise never run.
check_suites_listed() {
  local path name
  for path in "$tests_dir"/*.sh; do
    name="$(basename -- "$path")"
    [[ "$name" == mock-*.sh || "$name" == run-all.sh ]] && continue
    [[ " ${shell_suites[*]} " == *" $name "* ]] || stop_on_failure 1 "suite list (tests/$name is not in run-all.sh)"
  done
}

check_suites_listed
echo "== node --test tests/*.test.cjs"
(cd "$repo_dir" && node --test tests/*.test.cjs) || stop_on_failure $? 'node --test'
for entry in "${shell_suites[@]}"; do
  read -r suite test_case <<<"$entry"
  run_suite "$suite" "$test_case"
done
echo OMADROID_ALL_OK
