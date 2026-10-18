# Architecture Decision Records

Each record describes one decision in OmaDroid's design: the context that led
to it, what was decided, and what follows from it. They use Michael Nygard's
format (Title, Status, Context, Decision, Consequences) and are numbered in
the order the decisions were made. Dates and commit ids come from the git
history. For how the parts fit together today, see the
[architecture overview](../architecture.md).

| # | Decision | Date | Status |
| --- | --- | --- | --- |
| [1](0001-one-process-wide-discovery-service.md) | One process-wide discovery service shared by all widgets | 2026-09-12 | Accepted |
| [2](0002-one-scrcpy-session-per-machine.md) | One scrcpy session per machine, tracked by a state file | 2026-09-23 | Accepted |
| [3](0003-push-based-device-discovery.md) | Push-based device discovery, with polling only as a fallback | 2026-10-04 | Accepted |
| [4](0004-unlock-pin-in-keyring-bound-to-device.md) | Unlock PIN in the keyring, one attempt, bound to the device identity | 2026-10-04 | Accepted |
| [5](0005-external-config-only-via-install-button.md) | External config changes only through an explicit Install button | 2026-10-15 | Accepted |
| [6](0006-audio-codes-from-framework-jar.md) | Per-app volume through IAudioService codes read from framework.jar | 2026-10-16 | Accepted |
| [7](0007-rename-to-omadroid-without-migration.md) | Rename DroidLink to OmaDroid as a fresh start, without data migration | 2026-10-18 | Accepted |
| [8](0008-offscreen-preview-harness.md) | Offscreen preview and smoke harness instead of desktop windows | 2026-10-18 | Accepted |
| [9](0009-device-centric-popup.md) | Device-centric popup instead of six flat tabs | 2026-10-18 | Accepted |
| [10](0010-starting-a-session-switches-to-it.md) | Starting a session while another runs switches to it | 2026-10-18 | Accepted |
| [11](0011-qualify-theme-color-for-qt-6-12.md) | Qualify the theme `Color` as `Commons.Color` (Qt 6.12) | 2026-10-18 | Accepted |
| [12](0012-small-js-modules.md) | Keep modules small: split by responsibility, files under 500 lines | 2026-10-18 | Accepted |

## Adding a record

Copy the shape of an existing record, take the next number, and add a row
here. A record that is replaced is not edited away: set its status to
"Superseded by N" and link the new one.
