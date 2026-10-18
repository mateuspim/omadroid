# 11. Qualify the theme `Color` as `Commons.Color` (Qt 6.12)

- Status: Accepted
- Date: 2026-10-18 (`96b179a`)

## Context

OmaDroid's QML used the Omarchy theme singleton from `qs.Commons` unqualified
(`Color.accent`, `Color.foreground`). Qt 6.12's `QtQuick` module exports its
own `Color`, which wins the unqualified lookup, so every theme colour came back
undefined and the popup lost its theme.

## Decision

Like Omarchy's own Ui kit (4.0.5), every QML file that uses theme colours
imports `qs.Commons as Commons` and writes `Commons.Color.…`. The unqualified
`import qs.Commons` stays for `Style` and `Util`.

## Consequences

- Colours resolve the same on Qt 6.12 and earlier versions.
- New QML must use `Commons.Color`; an unqualified `Color.x` breaks silently
  (no load error, just undefined colours), so reviews and offscreen previews
  have to catch it.
