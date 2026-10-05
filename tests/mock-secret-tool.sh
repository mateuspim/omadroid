#!/usr/bin/env bash
# Keyring fixture: one file per `device` attribute under DROIDLINK_KEYRING.
# Every argv is logged so tests can prove the secret never travels in one.
set -eu
printf '%s\n' "$*" >>"$DROIDLINK_KEYRING/argv"
[[ "${DROIDLINK_TEST_CASE:-}" != keyring_locked ]] || exit 1
action="$1"
shift
[[ "$action" == store ]] && shift
[[ "$1 $2 $3" == 'app droidlink device' ]] || exit 9
case "$action" in
  store) cat >"$DROIDLINK_KEYRING/$4" ;;
  lookup) cat "$DROIDLINK_KEYRING/$4" 2>/dev/null ;;
  clear) rm -f -- "$DROIDLINK_KEYRING/$4" ;;
  *) exit 9 ;;
esac
