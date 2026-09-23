#!/usr/bin/env bash
set -eu
[[ "${1:-}" == --print-id ]] || exit 2
echo mock-terminal.desktop
