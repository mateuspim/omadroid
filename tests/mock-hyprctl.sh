#!/usr/bin/env bash
# Records compositor requests instead of changing the desktop. `clients -j`
# answers from OMADROID_HYPRCTL_CLIENTS when a test provides a window list.
printf '%s\n' "$*" >>"${OMADROID_HYPRCTL_LOG:?}"
if [[ "$*" == 'clients -j' && -n "${OMADROID_HYPRCTL_CLIENTS:-}" ]]; then
  cat -- "$OMADROID_HYPRCTL_CLIENTS"
  exit
fi
echo ok
