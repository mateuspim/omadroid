# DroidLink

An Omarchy bar widget for discovering Android Debug Bridge (ADB) devices over
USB and wireless mDNS, then launching scrcpy with chosen video and audio
settings.

## Current status

This initial scaffold validates as an Omarchy bar widget and provides a small
placeholder panel. Device discovery and scrcpy actions are deliberately not
implemented yet.

## Planned milestones

1. Read USB devices from `adb devices -l`.
2. Read wireless-debugging endpoints from `adb mdns services`.
3. Add connect, pair, disconnect, and copy-address actions.
4. Launch scrcpy with named quality, resolution, frame-rate, and audio presets.
5. Add optional recording and V4L2/OBS-oriented broadcast workflows.

## Development

Validate the plugin:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/pym.droidlink
```

The Omarchy shell hot-reloads changes under the user plugins directory.
