#!/usr/bin/env bash
# Keeps OmaDroid's own settings file owner-only: it holds remembered device
# ids and the last device's address.
#
#   settings-file.sh PATH → nothing; creates PATH empty if missing
#
# Run once at startup, before anything is saved. Qt replaces the file on every
# save but keeps its permissions, so a file created here stays 600, and one an
# older version left at 644 is tightened.
set -uo pipefail
file="${1:?usage: settings-file.sh PATH}"
umask 077
mkdir -p -- "$(dirname -- "$file")" || exit 1
[[ -e "$file" ]] || : >>"$file" || exit 1
chmod go= -- "$file"
