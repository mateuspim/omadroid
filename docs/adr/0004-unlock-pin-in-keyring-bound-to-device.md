# 4. Unlock PIN in the keyring, one attempt, bound to the device identity

- Status: Accepted
- Date: 2026-10-04 (`9bc5230`); identity binding 2026-10-18 (`5f4a4eb`)

## Context

Waking and unlocking a device before mirroring needs its PIN or password. A
secret typed over adb is easy to leak (settings files, logs, process
arguments), and a wrong one counts towards Android's lockout and wipe limits.
Wireless adb addresses change and can be reused by another device. The first
version keyed the secret by the hardware serial (`ro.serialno`), but Wireless
debugging advertises that serial over mDNS (`adb-<serial>-…`), so a LAN host
could advertise it, report it back and receive the PIN.

## Decision

- The secret is stored only in the desktop keyring with `secret-tool`
  (attributes `app omadroid`, `device <ro.serialno>`, `identity <hash>`),
  never in `omadroid.ini`, logs or any host process's arguments. Saving takes
  it on stdin; unlock looks it up inside `device-power.sh`, so it never enters
  QML on unlock.
- Devices are keyed by their live `ro.serialno`, never by adb address.
- Saving also records `sha256(ro.serialno + "\n" + android_id)` in the state
  dir and the keyring item. `android_id` is not advertised, and only its hash
  is kept. Unlock reads both values again and refuses (exit 6), before
  anything is typed and without spending the attempt, if they differ; a PIN
  saved without a hash must be saved again (`stale`).
- One attempt: the bouncer is opened (`wm dismiss-keyguard`) and typing starts
  only when `uiautomator` shows a PIN or password field. A `blocked` marker is
  written before typing; if the lock screen stays, unlock is paused until the
  secret is saved again.
- Only printable ASCII (4–64 characters) is accepted at save time, since
  `input text` can't type anything else; pattern locks are refused.

## Consequences

- A wrong or outdated PIN costs at most one Android attempt.
- A device that only copies the serial, or turns up on a reused address, never
  receives the PIN. It is not a defence against someone who already has adb
  access to the device, who can read the same `android_id`.
- After a factory reset (`android_id` changes) the PIN must be saved again.
- While it is typed, the secret briefly appears in the arguments of the
  device's own `input` command.
- `tests/device-power.sh` checks that the secret never appears in any argv,
  that a mismatched serial or `android_id` keeps the attempt, and that the raw
  `android_id` is never stored.
