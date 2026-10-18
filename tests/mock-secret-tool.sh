#!/usr/bin/env bash
# Keyring fixture: one file per `device` attribute under OMADROID_KEYRING, its
# `identity` attribute in DEVICE.identity. A lookup naming an identity matches
# only an item stored with that identity, as libsecret's attribute match does.
# Every argv is logged so tests can prove the secret never travels in one.
set -eu
printf '%s\n' "$*" >>"$OMADROID_KEYRING/argv"
[[ "${OMADROID_TEST_CASE:-}" != keyring_locked ]] || exit 1
action="$1"
shift
[[ "$action" == store ]] && shift
[[ "$1 $2 $3" == 'app omadroid device' ]] || exit 9
item="$OMADROID_KEYRING/$4"
identity=""
[[ $# == 4 ]] || { [[ $# == 6 && "$5" == identity ]] || exit 9; identity="$6"; }
case "$action" in
  store)
    cat >"$item"
    printf '%s' "$identity" >"$item.identity"
    ;;
  lookup)
    [[ -z "$identity" || "$(cat "$item.identity" 2>/dev/null)" == "$identity" ]] || exit 1
    cat "$item" 2>/dev/null
    ;;
  clear) rm -f -- "$item" "$item.identity" ;;
  *) exit 9 ;;
esac
