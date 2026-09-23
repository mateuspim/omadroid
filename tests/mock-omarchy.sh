#!/usr/bin/env bash
set -eu
[[ "${1:-}" == launch && "${2:-}" == terminal ]] || exit 2
shift 2
[[ "${1:-}" == --app-id=org.omarchy.droidlink && "${2:-}" == --hold && "${3:-}" == --title=DroidLink ]] || exit 2
shift 3
[[ "${1:-}" == -- ]] || exit 2
shift
exec "$@"
