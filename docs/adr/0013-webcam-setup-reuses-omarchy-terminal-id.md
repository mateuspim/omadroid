# 13. The webcam setup terminal reuses Omarchy's `org.omarchy.terminal` app-id

- Status: Accepted
- Date: 2026-10-18

## Context

**Set up webcam** opens a visible terminal so that `omarchy pkg add` and `sudo`
can ask for a password (`scripts/webcam-setup.sh open`). A tiled window that
appears beside the popup is easy to miss, so the window should float and
centre, like Omarchy's own setup prompts. OmaDroid's own terminal app-id is
`io.github.mateuspim.omadroid`, and no Hyprland rule matches it.

Alternatives considered:

- A plugin-owned float rule. A Hyprland rule lives in the user's config, and
  OmaDroid writes there only through an explicit Install button (ADR 5). That
  is a lot for a window most people open once.
- Exec rules (`hyprctl dispatch exec "[float; center] …"`). These match the
  launched PID. `omarchy launch terminal` and single-instance terminals hand the
  window to a different process, so the rule would apply only some of the time.

## Decision

The setup terminal launches with app-id `org.omarchy.terminal`. Omarchy's
built-in window rules (`default/hypr/apps/system.lua`) already float and centre
it. This is the only place OmaDroid uses an `org.omarchy.*` id. It reuses an id
Omarchy defines and doesn't add a new one. The scrcpy session terminal keeps
`io.github.mateuspim.omadroid`.

## Consequences

- The setup window floats and centres without touching the user's config.
- OmaDroid depends on an Omarchy rule it doesn't own. If Omarchy renames or
  drops that rule, the window tiles but still works. Check
  `default/hypr/apps/system.lua` when Omarchy changes its window rules.
