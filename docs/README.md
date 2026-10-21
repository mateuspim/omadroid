# OmaDroid documentation

## Use OmaDroid

- [README](../README.md): what OmaDroid is, install and remove.
- Guide:
  - [Features](guide/features.md): the device list, device pages, session
    cards and keyboard use.
  - [Requirements and enabling](guide/requirements.md): what to install and
    how OmaDroid fits into Omarchy and Hyprland.
  - [Connecting a device](guide/connecting.md): USB, wireless debugging, QR
    pairing, going wireless and auto-connect.
  - [Mirroring and profiles](guide/mirroring.md): profiles, phone screen,
    rotation, recording and how sessions run.
  - [Android webcam setup](guide/webcam.md): the v4l2loopback output, camera
    options and preview.
  - [Keep awake and unlock](guide/keep-awake-and-unlock.md): keep awake,
    lock and the keyring PIN.
  - [Sound](guide/sound.md): volume keys, ringer, per-app volume and streams.
  - [Send text](guide/send-text.md): the prompt, its keys and the hotkey.
- [Troubleshooting](runbooks/troubleshooting.md): messages, causes and fixes.
- [Security and privileges](../SECURITY.md).
- [Brand assets](branding.md): icon, wordmarks and README hero.

## Develop OmaDroid

- [Architecture](architecture.md): components and data flow.
- [Architecture decisions](adr/README.md): durable tradeoffs.
- Specs: [settings file](specs/settings.md),
  [environment variables](specs/environment.md),
  [shell integration](specs/shell-integration.md) (entry points, service,
  Send text overlay) and the [script contract](specs/scripts.md) QML parses.
- [Development runbook](runbooks/development.md): setup, tests, offscreen
  previews, refreshing the hero, releases.
- [Contributing](../CONTRIBUTING.md) and [agent instructions](../AGENTS.md).
- [Changelog](../CHANGELOG.md).
