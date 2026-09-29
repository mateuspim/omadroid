#!/usr/bin/env bash
set -eu
case "${1:-}" in
  devices)
    if [[ -n "${DROIDLINK_ADB_LOG:-}" ]]; then
      if ! mkdir "${DROIDLINK_ADB_LOG}.lock" 2>/dev/null; then
        printf '%s\n' overlap >>"$DROIDLINK_ADB_LOG"
      else
        trap 'rmdir -- "${DROIDLINK_ADB_LOG}.lock"' EXIT
      fi
      discovery_phase=initial
      if [[ -n "${DROIDLINK_REFRESH_MARKER:-}" && -e "$DROIDLINK_REFRESH_MARKER" ]]; then
        discovery_phase=refresh
      fi
      printf 'start %s %s\n' "$discovery_phase" "$$" >>"$DROIDLINK_ADB_LOG"
      sleep 0.15
    fi
    printf '%s\n' 'List of devices attached' \
      'USB123 device usb:1-2 product:oriole model:Pixel_6 device:oriole transport_id:1' \
      'LOCKED unauthorized usb:1-3' \
      '192.168.1.3:5555 offline' \
      'adb-PHONE-random._adb-tls-connect._tcp device model:Pixel_9'
    if [[ -n "${DROIDLINK_ADB_LOG:-}" ]]; then
      printf 'end %s %s\n' "$discovery_phase" "$$" >>"$DROIDLINK_ADB_LOG"
    fi
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
  -s)
    # Emulates Android's rotation settings in DROIDLINK_ADB_ROTATION as the two
    # lines `settings get` prints: accelerometer_rotation, then user_rotation.
    [[ "${3:-}" == shell ]] || exit 7
    serial="$2"
    shift 3
    if [[ "$*" == 'settings get global device_name' ]]; then
      # USB123 has a name set on the phone; other devices report none.
      [[ "$serial" == USB123 ]] && printf 'Desk phone\r\n' || printf 'null\r\n'
      exit 0
    fi
    rotation_state="${DROIDLINK_ADB_ROTATION:?}"
    case "$*" in
      'wm user-rotation free') printf '1\n0\n' >"$rotation_state" ;;
      'wm user-rotation lock '[0-3]) printf '0\n%s\n' "${*: -1}" >"$rotation_state" ;;
      'settings get system accelerometer_rotation; settings get system user_rotation')
        # Real adb shells end lines with CRLF.
        sed 's/$/\r/' "$rotation_state" 2>/dev/null || printf '1\r\nnull\r\n'
        ;;
      *) exit 7 ;;
    esac
    ;;
  *) exit 7 ;;
esac
