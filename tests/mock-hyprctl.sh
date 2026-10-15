#!/usr/bin/env bash
# Records compositor requests instead of changing the desktop. `clients -j`
# answers from DROIDLINK_HYPRCTL_CLIENTS when a test provides a window list.
printf '%s\n' "$*" >>"${DROIDLINK_HYPRCTL_LOG:?}"
if [[ "$*" == 'clients -j' && -n "${DROIDLINK_HYPRCTL_CLIENTS:-}" ]]; then
  cat -- "$DROIDLINK_HYPRCTL_CLIENTS"
  exit
fi
echo ok
