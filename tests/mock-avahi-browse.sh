#!/usr/bin/env bash
set -eu
if [[ "${DROIDLINK_TEST_CASE:-}" == avahi_unavailable ]]; then
  printf '%s\n' 'Failed to create client object: Daemon not running' >&2
  exit 1
fi
case "${*: -1}" in
  _adb._tcp) ;;
  _adb-tls-connect._tcp)
    printf '%s\n' \
      '=;eno1;IPv4;adb-PHONE-random;_adb-tls-connect._tcp;local;phone.local;192.168.1.4;37001;"api=36" "name=SM-X730" "v=1"' \
      '=;eno1;IPv4;adb-NEW-random;_adb-tls-connect._tcp;local;new.local;192.168.1.5;37002;' \
      '=;wlan0;IPv4;adb-NEW-random;_adb-tls-connect._tcp;local;new.local;192.168.1.5;37002;' \
      '=;eno1;IPv4;removed;_adb-tls-connect._tcp;local;gone.local;192.168.1.9;1234;' \
      '-;eno1;IPv4;removed;_adb-tls-connect._tcp;local'
    ;;
  _adb-tls-pairing._tcp)
    if [[ "${DROIDLINK_TEST_CASE:-}" == partial ]]; then
      printf '%s\n' 'Pairing resolver failed (fixture)' >&2
      exit 1
    fi
    printf '%s\n' '=;eno1;IPv4;adb-NEW-pair;_adb-tls-pairing._tcp;local;new.local;192.168.1.5;42000;'
    ;;
  *) exit 7 ;;
esac
# Without --terminate a real browser keeps following until it is signalled.
# Keeping the fixture path in argv lets tests find leftover browsers.
[[ " $* " == *' --terminate '* ]] || exec -a "$0" sleep 30
