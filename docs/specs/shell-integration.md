# Shell integration: entry points, service and overlay

How OmaDroid plugs into the Omarchy shell, and the calls other parts of the
shell (and the user's key binding) can make into it. The architecture
overview explains the parts; this page is the contract.

## Entry points

`manifest.json` (plugin id `pym.omadroid`) declares:

| Kind | Entry point | Instances |
| --- | --- | --- |
| `service` | `Discovery.qml` | One per shell process |
| `bar-widget` | `Panel.qml` | One per bar (`allowMultiple: false` per bar, default section `right`) |
| `overlay` | `SendText.qml` | The Send text prompt |

## Overlay: Send text

Summon or dismiss the prompt with:

```bash
omarchy-shell shell toggle pym.omadroid
```

- The shell calls `SendText.open(payloadJson)` on every summon. The payload
  is ignored; the prompt resets and picks its device from the
  `lastTextTarget` preference while that device is ready, else the first
  ready device.
- The overlay closes itself through `shell.hide("pym.omadroid")` after
  sending, on Escape, or on a click outside the card.
- The bar's **Text** control sets `lastTextTarget` to the page's device, closes
  the popup and calls `shell.toggle("pym.omadroid", "")`.
- The window is a full-screen `PanelWindow` on the overlay layer with
  exclusive keyboard focus and layer namespace `omadroid-send-text`.

The key binding is optional. `scripts/hotkey.sh` writes it, only when the user
clicks **Install** on the Settings page, as this marked block at the end of
`~/.config/hypr/bindings.lua`:

```lua
-- >>> OmaDroid send text (managed by OmaDroid; change it on its Settings page)
o.bind("SUPER + ALT + D", "OmaDroid send text", "omarchy-shell shell toggle pym.omadroid")
-- <<< OmaDroid send text
```

## Service: discovery

Widgets reach the service with `shell.serviceFor("pym.omadroid")`, wrapped by
`DiscoveryConsumer.qml`. Without a shell the consumer exposes an empty
stand-in with the same read-only properties, so a widget still loads.

Calls (through `DiscoveryConsumer`):

| Call | Effect |
| --- | --- |
| `refresh()` | Rescan adb devices now (queued, never overlapping). |
| `holdMdns(wanted)` | While any consumer holds it (an open popup), the Avahi browsers run and device details are read. |
| `setPreference(name, value)` | Write a `[preferences]` key; see [settings](settings.md). Unknown names throw. |
| `setAutoConnect(on)` | Turn auto-connect on or off. |

Read-only state the widgets bind to: `devices`, `services`, `rows`,
`readyCount`, `devicesError`, `mdnsError`, `mdnsLevel`, `mdnsDetails`,
`updatedAt`, `initialized`, `refreshPending`, `busy`, `tracking`,
`intervalSec`, `autoConnect` and `preferences`.

## Hyprland

OmaDroid touches Hyprland only at run time and only for its own windows:

- The scrcpy session runs in a terminal with app-id
  `io.github.mateuspim.omadroid`, sent by a named window rule (`hyprctl eval`)
  to the hidden `special:omadroid` workspace. **Log** toggles that workspace.
- The webcam setup terminal reuses `org.omarchy.terminal`, so Omarchy floats
  it ([ADR 13](../adr/0013-webcam-setup-reuses-omarchy-terminal-id.md)).
- The running mirror's screen controls send scrcpy's own display-power
  shortcut to the scrcpy window by PID (`hyprctl dispatch`): `Alt+Shift+O`
  turns the phone's screen on, `Alt+O` off. Only Hyprland's `ok` reply counts
  as success.

## Keyring

Unlock secrets are stored with `secret-tool` under the attributes
`app omadroid`, `device <ro.serialno>` and `identity <sha256>`; see
[ADR 4](../adr/0004-unlock-pin-in-keyring-bound-to-device.md).
