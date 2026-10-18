#!/usr/bin/env bash
# Keyring fixture: one file per `device` attribute under OMADROID_KEYRING.
# Every argv is logged so tests can prove the secret never travels in one.
set -eu
printf '%s\n' "$*" >>"$OMADROID_KEYRING/argv"
[[ "${OMADROID_TEST_CASE:-}" != keyring_locked ]] || exit 1
action="$1"
shift
[[ "$action" == store ]] && shift
[[ "$1 $2 $3" == 'app omadroid device' ]] || exit 9
case "$action" in
  store) cat >"$OMADROID_KEYRING/$4" ;;
  lookup) cat "$OMADROID_KEYRING/$4" 2>/dev/null ;;
  clear) rm -f -- "$OMADROID_KEYRING/$4" ;;
  *) exit 9 ;;
esac
