# Send text

Type on a device from a centered prompt opened by a hotkey or the Text control.

A centered prompt, like Omarchy's reminder prompt, that types on a device with
`adb shell input text`. Focus a text field on the device, open the prompt, type,
and press Enter. A device page's **Text** control opens the prompt on that
device.

Omarchy has no way for a plugin to bind keys, so the **Send text hotkey** row
in Settings (⚙) writes the binding into `~/.config/hypr/bindings.lua`. Pick a
combination (`SUPER + ALT + D` by default) and press **Install**. OmaDroid
appends one marked block and changes nothing else in the file:

```lua
-- >>> OmaDroid send text (managed by OmaDroid; change it on its Settings page)
o.bind("SUPER + ALT + D", "OmaDroid send text", "omarchy-shell shell toggle pym.omadroid")
-- <<< OmaDroid send text
```

**Update** replaces that block, and **Remove** deletes it. Each change keeps a
`bindings.lua.bak.<epoch>` copy (only the 2 newest are kept) and reloads
Hyprland. If the start marker is there without its end marker (the block was
edited by hand), the file is left untouched and OmaDroid asks you to restore
or delete the block yourself. A combination that
`omarchy menu keybindings --print` already lists is refused with the name of
its binding. A symlinked `bindings.lua` (dotfiles) is written through and stays
a symlink. Without the plugin's UI: `scripts/hotkey.sh set "SUPER + ALT + D"`,
`scripts/hotkey.sh status`, `scripts/hotkey.sh remove`. Running the bound command again closes
the prompt.

- **Typing:** letters, digits and symbols are typed as text. Other keys you
  press are **recorded** as key chips in the prompt, in order: Ctrl/Alt
  combinations (Ctrl+A, Ctrl+Backspace, …), Tab and Shift+Tab, Delete,
  Home/End, the arrows, PgUp/PgDn, Insert, F1–F12. So
  `Ctrl+A`, `Ctrl+K Backspace`, `new text`, `Tab` builds a small macro that
  selects all, deletes, types and moves to the next field. Nothing reaches the
  device until you send.
- **The prompt's own keys:** **Enter** sends; **Shift+Enter** sends and then
  presses Enter on the device; **Ctrl+Enter** first clears the device's focused
  field (End, Shift+Home, Backspace), and with an empty prompt only clears it;
  **Ctrl+Shift+Enter** clears, sends and presses Enter. **Backspace** deletes
  the last character or chip. **Esc** clears the prompt, then closes it.
  **Ctrl+V** / **Shift+Insert** paste. **Ctrl+K** records the next key whatever
  it is, for a Backspace, Enter or Esc inside the macro. **Alt+←/→** switches
  the device.
- **Device:** with one ready device it is used. With several, a row shows them
  all and **Alt+←/→** switches. The device you last typed on is remembered
  (`lastTextTarget` in `omadroid.ini`) and preselected while it is ready;
  otherwise the first ready device is. With none, the prompt says so and Enter
  does nothing.
- The prompt closes once the text is typed. If adb fails, it stays open with
  adb's message so you can retry.
- `input text` only types printable ASCII. Accents, emoji, tabs or line breaks
  are named in a `⚠` warning and nothing is sent.
- Ctrl+Enter avoids Ctrl on purpose: some apps react to Ctrl itself. YouTube
  opens its keyboard-shortcut list on any Ctrl press, and that list then takes
  the keys sent after it. A recorded Ctrl+A chip is sent as a real Ctrl+A, so it
  does that too there. Ctrl+Enter only clears the last line of a multi-line field.
- A literal `%s` is typed as a space: `input text` uses it to spell a space and
  has no escape for it.

The overlay is `SendText.qml` (window), `SendTextCard.qml` (prompt and keys)
and `SendTextSteps.qml` (text and chips);
`scripts/send-text.sh` does the typing and can be run on its own, with one step
per line on stdin:
`printf '%s\n' key:ctrl+a key:backspace "text:hello world" key:enter | scripts/send-text.sh SERIAL`.
Steps are refused as arguments, which other local users could read in a
process listing. It checks every step first, then sends them all in one
`adb shell` call, on adb's stdin too. Key
names: a letter, digit or `f1`–`f12`; `enter`, `tab`, `space`, `backspace`,
`del`, `esc`, `home`, `end`, `up`, `down`, `left`, `right`, `pageup`,
`pagedown`, `insert`, and Android's `back`, `menu`, `search`; prefix `ctrl+`,
`shift+`, `alt+` or `meta+` for a combination (Android 13+, sent with
`input keycombination`).
