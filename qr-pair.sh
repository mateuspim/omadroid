#!/usr/bin/env bash
# Make a one-time code for Android's Wireless debugging › Pair device with QR
# code. Android scans WIFI:T:ADB;S:<service>;P:<password>;; and then announces
# _adb-tls-pairing._tcp under that service name; OmaDroid waits for it and
# runs `adb pair` with the password.
# stdout: "service<TAB>name", "password<TAB>secret", then "row<TAB>0110…" per
# QR row (1 is a dark module, no quiet zone). stderr: why it failed.
set -euo pipefail
export LC_ALL=C

command -v qrencode >/dev/null 2>&1 || {
  printf '%s\n' 'Missing qrencode. Install qrencode to pair with a QR code.' >&2
  exit 1
}

# 32 symbols, so a byte modulo 32 picks each one evenly. Look-alikes (l, o, 0, 1)
# are left out in case the code is ever read aloud.
random_text() {
  local alphabet=abcdefghijkmnpqrstuvwxyz23456789 text="" byte
  for byte in $(od -An -N"$1" -tu1 /dev/urandom); do
    text+="${alphabet:byte % 32:1}"
  done
  printf '%s' "$text"
}

service="omadroid-$(random_text 8)"
password="$(random_text 16)"
printf 'service\t%s\npassword\t%s\n' "$service" "$password"
# The payload goes on stdin, so the password never shows in a process list.
# qrencode's ASCII output draws each module two characters wide.
printf 'WIFI:T:ADB;S:%s;P:%s;;' "$service" "$password" | qrencode -t ASCII -m 0 -l M |
  sed 's/##/1/g; s/  /0/g; s/^/row\t/'
