# OmaDroid brand assets

The mark is an Android head over a terminal prompt (`>_`): Android on the
Omarchy desktop. It is drawn on a 24-unit grid as vector paths, so it stays
readable at 32 px; at 16 px the eyes close up and it reads as a dome over a
prompt. [`icon.svg`](../icon.svg) is single-colour (`currentColor`: `#1f2328`
on light pages, `#e6edf3` on dark ones), and `DroidPromptIcon.qml` draws the
same shape natively in the bar, in the bar's foreground colour.

## Colours

Sampled from the shipped [`preview.png`](../preview.png):

| Role | Colour |
| --- | --- |
| Accent: mark, "Droid", chip glyphs, `$` | `#3ddc84` |
| Accent on light surfaces (`logo-light.svg`) | `#1a9455` |
| Wordmark "Oma", tagline, chip text | `#e6edf3` |
| Subline | `#8b949e` |
| Background | `#0b0f14`, green glow bottom-left, blue glow top-right, 56 px dot grid |
| Feature chips | fill `#151b20`, stroke `#30363d` |
| Install box | fill `#0e1218`, stroke `#30363d` |
| Panel captures | surface `#101315`, frame `#30363d` |

The accent is in the house `#37da88` green family but slightly brighter and
yellower; keep `#3ddc84` for OmaDroid so new assets match the shipped hero.

## Assets

| Asset | Use |
| --- | --- |
| [`icon.svg`](../icon.svg) | Square app icon and README heading. |
| [`logo.svg`](brand/logo.svg) | Horizontal wordmark on a dark surface. |
| [`logo-light.svg`](brand/logo-light.svg) | Horizontal wordmark on a light surface. |
| [`preview.svg`](brand/preview.svg) | Editable README hero layout. |
| [`captures/`](brand/captures/) | Offscreen popup renders with fake devices, placed by `preview.svg`. |
| [`preview.png`](../preview.png) | Rendered README hero at 3840 × 2160. |

The logo SVGs and the preview inline the mark so they render standalone; keep
the paths in sync when changing the icon. Wordmarks use live SVG text in
JetBrains Mono (falling back to DejaVu Sans Mono), so the font can vary where
JetBrains Mono is not installed.

`preview.svg` was rebuilt from measurements of the shipped `preview.png`. It
approximates it: the shipped image tilts the two panels with a slight
perspective that SVG cannot express, so the SVG uses flat rotations instead.
The shipped PNG was kept; render the SVG over it only when the layout or the
captures change.

Keep clear space around the mark and the wordmark casing **OmaDroid**. The
[development runbook](runbooks/development.md#refresh-the-preview) explains how
to re-render the hero from offscreen captures with fake data.
