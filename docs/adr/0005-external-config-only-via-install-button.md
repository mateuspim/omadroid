# 5. External config changes only through an explicit Install button

- Status: Accepted
- Date: 2026-10-15 (`f03d7e1`); unclosed-block refusal and backup pruning
  2026-10-18 (`868484f`)

## Context

The Send text overlay needs a global hotkey, and Omarchy gives plugins no way
to bind keys. Asking users to hand-edit Hyprland's `bindings.lua` is not
reproducible on a new machine, and a plugin that edits user config on its own
can damage it. The same tension exists elsewhere: the hidden session terminal
needs a window rule, and the webcam needs a `v4l2loopback` module.

## Decision

External configuration is changed only by an explicit action in OmaDroid's
own UI, and only within a block OmaDroid owns.

- The **Send text hotkey** row in Settings runs `hotkey.sh set COMBO`,
  `status` or `remove`. It keeps exactly one marked block at the end of
  `bindings.lua`, between `-- >>> OmaDroid send text …` and
  `-- <<< OmaDroid send text`, and never touches anything outside it.
- Each change keeps a `bindings.lua.bak.<epoch>` copy (the 2 newest are kept),
  writes through a symlinked file, and reloads Hyprland.
- A combination that `omarchy menu keybindings --print` already lists is
  refused with that binding's name. A start marker without its end marker
  makes the file be refused untouched rather than rewritten.
- The same rule applies elsewhere: the session terminal's window rule is
  registered at runtime with `hyprctl eval` (no config edit), and webcam setup
  (`webcam-setup.sh`) runs in a visible terminal only after a click, keeping
  any existing `v4l2loopback` config.
- OmaDroid's own options live in its own `omadroid.ini`, never in Omarchy's
  configuration.

## Consequences

- A fresh setup gets the hotkey from one click, and the user can see, update
  or remove it from the same place.
- Opening the popup never installs, loads or edits anything.
- Hand edits inside the marked block may be replaced by the next Update.
- `tests/hotkey.sh` covers set/update/remove, taken combinations, symlinks,
  backups and the unclosed block.
