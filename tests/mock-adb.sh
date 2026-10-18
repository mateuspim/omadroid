#!/usr/bin/env bash
set -eu
export LC_ALL=C
device_rows() {
  printf '%s\n' 'USB123 device usb:1-2 product:oriole model:Pixel_6 device:oriole transport_id:1' \
    'LOCKED unauthorized usb:1-3' \
    '192.168.1.3:5555 offline' \
    'adb-PHONE-random._adb-tls-connect._tcp device model:Pixel_9'
}
# device-power.sh fixture: OMADROID_POWER_DIR holds `awake` and `locked`
# flags, the `password` that unlocks and optionally USB123's `android_id`. Typed scripts are evaluated like the
# device shell would, so quoting mistakes change what gets typed.
mock_power() {
  local serial="$1" dir="$OMADROID_POWER_DIR" line typed=""
  shift
  printf '%s\n' "$*" >>"$dir/argv"
  case "$*" in
    'getprop ro.serialno') [[ "$serial" == USB123 ]] && printf 'R5CR123ABC\r\n' || printf 'OTHERDEVICE\r\n' ;;
    # `android_id` overrides USB123's id, modelling an impostor that reports
    # the right serial (it is visible over mDNS) but can't know this id.
    'settings get secure android_id')
      [[ "$serial" == USB123 ]] && printf '%s\r\n' "$(cat "$dir/android_id" 2>/dev/null || echo 9f3a61c2d4e5b708)" || printf '0123456789abcdef\r\n'
      ;;
    'input keyevent KEYCODE_WAKEUP') touch "$dir/awake" ;;
    'input keyevent KEYCODE_SLEEP')
      # lock_delay: keyguard comes later; sleep_ignored: screen stays on.
      [[ "${OMADROID_TEST_CASE:-}" == sleep_ignored ]] && return 0
      rm -f "$dir/awake"
      [[ "${OMADROID_TEST_CASE:-}" == lock_delay ]] || touch "$dir/locked"
      ;;
    'dumpsys power'*)
      [[ -e "$dir/awake" ]] && printf '  mWakefulness=Awake\r\n' || printf '  mWakefulness=Dozing\r\n'
      [[ -e "$dir/locked" ]] && printf '    isKeyguardShowing=true\r\n' || printf '    isKeyguardShowing=false\r\n'
      ;;
    'input keyevent KEYCODE_WAKEUP; sleep 0.3; wm dismiss-keyguard'*)
      touch "$dir/awake"
      [[ "${OMADROID_TEST_CASE:-}" == pattern ]] && printf '<node resource-id="com.android.systemui:id/lockPatternView"/>\r\n' ||
        printf '<node resource-id="com.android.systemui:id/passwordEntry"/>\r\n'
      ;;
    '')
      cat >"$dir/script"
      while IFS= read -r line; do
        case "$line" in
          'input text '*) eval "set -- ${line#input text }"; typed+="$1" ;;
          'input keyevent KEYCODE_SPACE') typed+=" " ;;
          'input keyevent KEYCODE_ENTER')
            printf '%s' "$typed" >"$dir/typed"
            [[ "$typed" == "$(cat "$dir/password")" ]] && rm -f "$dir/locked"
            ;;
        esac
      done <"$dir/script"
      ;;
    *) return 7 ;;
  esac
}
# send-text.sh fixture: OMADROID_TEXT_DIR/typed collects what the device
# types, keys as <ENTER> or <CTRL+A>. The command string is evaluated like the
# device's sh would, so a quoting mistake changes what gets typed; %s is typed
# as a space, as Android does. OMADROID_TEST_CASE=input_error answers like an
# input command that threw; serial MISSING isn't connected.
mock_input() {
  local dir="$OMADROID_TEXT_DIR" space='%s' keys
  case "$1" in
    text) [[ $# == 2 ]] || return 9; printf '%s' "${2//$space/ }" >>"$dir/typed" ;;
    keyevent | keycombination)
      shift
      keys="$(printf '%s\n' "$@" | sed 's/^KEYCODE_//; s/_LEFT$//' | paste -sd+)"
      printf '<%s>' "$keys" >>"$dir/typed"
      ;;
    *) return 7 ;;
  esac
}
mock_text() {
  local dir="$OMADROID_TEXT_DIR"
  printf '%s\n' "$*" >>"$dir/argv"
  [[ "$serial" != MISSING ]] || { printf "adb: device 'MISSING' not found\n" >&2; return 1; }
  [[ "${OMADROID_TEST_CASE:-}" == input_error ]] && { printf 'java.lang.IllegalStateException: no window\r\n'; return 0; }
  input() { mock_input "$@"; }
  eval "$*"
}
# go-wireless.sh fixture: OMADROID_WIRELESS_DIR holds the device's `sdk`, its
# `ip -4 -o addr show` output in `addresses`, `enabled` (adb_wifi_enabled) and
# the `port` adbd publishes once enabled (`stale-port` before). Every adb call
# is appended to `log`. OMADROID_TEST_CASE=untrusted connects unauthorized.
mock_wireless_shell() {
  local dir="$OMADROID_WIRELESS_DIR"
  printf 'shell %s\n' "$*" >>"$dir/log"
  case "$*" in
    'getprop ro.build.version.sdk') printf '%s\r\n' "$(cat "$dir/sdk")" ;;
    'ip -4 -o addr show') sed 's/$/\r/' "$dir/addresses" ;;
    'settings get global adb_wifi_enabled') printf '%s\r\n' "$(cat "$dir/enabled")" ;;
    'settings put global adb_wifi_enabled 1') printf '1' >"$dir/enabled" ;;
    'getprop service.adb.tls.port')
      [[ "$(cat "$dir/enabled")" == 1 ]] && printf '%s\r\n' "$(cat "$dir/port")" || printf '%s\r\n' "$(cat "$dir/stale-port" 2>/dev/null)"
      ;;
    *) return 7 ;;
  esac
}
mock_wireless() {
  local dir="$OMADROID_WIRELESS_DIR"
  printf '%s\n' "$*" >>"$dir/log"
  case "$1" in
    connect) printf 'connected to %s\n' "$2" ;;
    -s)
      case "$3" in
        tcpip) printf 'restarting in TCP mode port: %s\n' "$4" ;;
        get-state) [[ "${OMADROID_TEST_CASE:-}" == untrusted ]] && printf 'unauthorized\n' || printf 'device\n' ;;
        shell) shift 3; mock_wireless_shell "$@" ;;
        *) return 7 ;;
      esac
      ;;
    *) return 7 ;;
  esac
}
# device-volume.sh fixture: tests/mock-volume-adb.sh answers its calls and
# exits 100 for anything else.
if [[ -n "${OMADROID_VOLUME_MOCK:-}" ]]; then
  volume_code=0
  bash "$OMADROID_VOLUME_MOCK" "$@" || volume_code=$?
  [[ "$volume_code" == 100 ]] || exit "$volume_code"
fi
if [[ -n "${OMADROID_WIRELESS_DIR:-}" ]]; then
  mock_wireless "$@"
  exit $?
fi
case "${1:-}" in
  track-devices)
    # no_track models an adb whose tracker fails, so discovery falls back to polling.
    [[ "${OMADROID_TEST_CASE:-}" != no_track ]] || { echo 'adb: unknown command track-devices' >&2; exit 1; }
    [[ -z "${OMADROID_ADB_LOG:-}" ]] || printf 'track %s\n' "$$" >>"$OMADROID_ADB_LOG"
    # Real framing: an empty list, then 4 hex digits of byte length and the rows.
    rows="$(device_rows)"$'\n'
    printf '0000%04x%s' "${#rows}" "$rows"
    exec sleep 30
    ;;
  devices)
    if [[ -n "${OMADROID_ADB_LOG:-}" ]]; then
      if ! mkdir "${OMADROID_ADB_LOG}.lock" 2>/dev/null; then
        printf '%s\n' overlap >>"$OMADROID_ADB_LOG"
      else
        trap 'rmdir -- "${OMADROID_ADB_LOG}.lock"' EXIT
      fi
      discovery_phase=initial
      if [[ -n "${OMADROID_REFRESH_MARKER:-}" && -e "$OMADROID_REFRESH_MARKER" ]]; then
        discovery_phase=refresh
      fi
      printf 'start %s %s\n' "$discovery_phase" "$$" >>"$OMADROID_ADB_LOG"
      sleep 0.15
    fi
    printf '%s\n' 'List of devices attached'
    device_rows
    if [[ -n "${OMADROID_ADB_LOG:-}" ]]; then
      printf 'end %s %s\n' "$discovery_phase" "$$" >>"$OMADROID_ADB_LOG"
    fi
    ;;
  connect)
    # 192.168.1.66 models a phone that no longer trusts this computer.
    if [[ "$2" == fail.local:* ]]; then printf '%s\n' "failed to connect to $2"
    elif [[ "$2" == 192.168.1.66:* ]]; then printf '%s\n' "failed to authenticate to $2"
    else printf '%s\n' "connected to $2"; fi
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
    # Emulates Android's rotation settings in OMADROID_ADB_ROTATION as the two
    # lines `settings get` prints: accelerometer_rotation, then user_rotation.
    [[ "${3:-}" == shell ]] || exit 7
    serial="$2"
    shift 3
    if [[ "$*" == 'getprop ro.build.version.sdk' ]]; then
      printf '%s\r\n' "${OMADROID_TEST_SDK:-36}"
      exit 0
    fi
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
    if [[ -n "${OMADROID_TEXT_DIR:-}" && ( "$*" == 'input text '* || "$*" == 'input key'* ) && "$*" != *KEYCODE_WAKEUP* && "$*" != *KEYCODE_SLEEP* ]]; then
      mock_text "$@"
      exit $?
    fi
    if [[ -n "${OMADROID_POWER_DIR:-}" ]]; then
      mock_power "$serial" "$@"
      exit $?
    fi
    rotation_state="${OMADROID_ADB_ROTATION:?}"
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
