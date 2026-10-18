# 7. Rename DroidLink to OmaDroid as a fresh start, without data migration

- Status: Accepted
- Date: 2026-10-18 (`46ca0f9`)

## Context

The plugin was developed privately as DroidLink (`pym.droidlink`) through
0.9.0. Publishing it needed a distinct name, an install path from GitHub and
no machine-specific details in the repository. Its data was spread over a
settings file, state and cache folders, a runtime folder, keyring items and
environment variables, all named after DroidLink, and the only existing
install was the author's own.

## Decision

- Rename everything at once: plugin id `pym.omadroid`, `OMADROID_*`
  environment variables, `omadroid.ini`, `omadroid` state, cache and runtime
  folders, keyring attribute `app omadroid`, and the session terminal app-id
  `io.github.mateuspim.omadroid` (a third-party plugin should not claim
  `org.omarchy.*`).
- Publish as https://github.com/mateuspim/omadroid with an MIT `LICENSE`;
  1.0.0 is the first public release, where `CHANGELOG.md` starts.
- Do not migrate DroidLink data. OmaDroid never reads `droidlink.ini`,
  DroidLink folders or keyring items; the one existing install was cleaned up
  by hand.

## Consequences

- No compatibility code to carry or test.
- Anyone who ran a DroidLink build starts fresh: profiles, Auto-connect
  devices and unlock PINs must be set up again, and DroidLink's files can be
  deleted.
- Git history before 1.0.0 still uses the DroidLink name.
