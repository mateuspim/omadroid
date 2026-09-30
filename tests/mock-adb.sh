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
    if [[ "$*" == 'echo @battery;'* ]]; then
      # device-info.sh: USB123 answers like a Samsung tablet (battery history
      # after the current state, an SD card); other devices don't answer.
      [[ "$serial" == USB123 ]] || exit 1
      printf '%s\r\n' '@battery' 'Current Battery Service state:' '  AC powered: false' '  USB powered: true' \
        '  Wireless powered: false' '  status: 2' '  health: 2' '  level: 64' '  temperature: 301' '  Capacity level: -1' \
        '09-28 21:34:19.289  Sending ACTION_BATTERY_CHANGED: level:90, status:3, temperature:282' \
        '@version' '16' '36' '@mem' 'MemTotal:       11788072 kB' '@size' 'Physical size: 1600x2560' \
        '@volumes' 'private mounted null' 'public:179,1 mounted 7934-B54D' 'emulated;0 mounted null' \
        '@df' 'Filesystem       1K-blocks      Used Available Use% Mounted on' \
        '/dev/block/dm-75 233775104 133125120 100518912  57% /data/user/0' \
        '/dev/fuse        999842816 122373248 877469568  13% /storage/7934-B54D' \
        '/dev/fuse        233775104 133125120 100518912  57% /storage/emulated' \
        'tmpfs              5491156         0   5491156   0% /storage'
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
