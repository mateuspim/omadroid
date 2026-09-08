#!/usr/bin/env bash
set -eu
case "${1:-}" in
  devices)
    printf '%s\n' 'List of devices attached' \
      'USB123 device usb:1-2 product:oriole model:Pixel_6 device:oriole transport_id:1' \
      'LOCKED unauthorized usb:1-3' \
      '192.168.1.3:5555 offline' \
      'adb-PHONE-random._adb-tls-connect._tcp device model:Pixel_9'
    ;;
  connect)
    if [[ "$2" == fail.local:* ]]; then printf '%s\n' "failed to connect to $2"; else printf '%s\n' "connected to $2"; fi
    ;;
  disconnect)
    [[ $# == 2 ]] || exit 9
    printf '%s\n' "disconnected $2"
    ;;
  pair)
    [[ $# == 2 ]] || exit 9
    IFS= read -r pair_code
    [[ "$pair_code" == 123456 ]] || exit 8
    printf '%s\n' "Successfully paired to $2 [guid=mock]"
    ;;
  *) exit 7 ;;
esac
