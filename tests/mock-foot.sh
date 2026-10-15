#!/usr/bin/env bash
# Stands in for foot: checks DroidLink's options, then runs the command in place.
set -eu
[[ "${1:-}" == --app-id=* && "${2:-}" == --title=* ]] || exit 2
[[ -n "${DROIDLINK_FOOT_LOG:-}" ]] && printf 'foot:%s\n' "$*" >> "$DROIDLINK_FOOT_LOG"
shift 2
[[ "${1:-}" != --hold ]] || shift
[[ "${1:-}" == -- ]] || exit 2
shift
exec "$@"
