#!/usr/bin/env bash
# Records compositor requests instead of changing the desktop.
printf '%s\n' "$*" >>"${DROIDLINK_HYPRCTL_LOG:?}"
echo ok
