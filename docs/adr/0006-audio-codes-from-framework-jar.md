# 6. Per-app volume through IAudioService codes read from framework.jar

- Status: Accepted
- Date: 2026-10-16 (`e095576`)

## Context

Stream volumes and the ringer have shell commands (`cmd audio`), but
Samsung's per-app volume and Android's master mute do not. They are reachable
only as hidden `IAudioService` binder methods (`service call audio CODE …`),
and the transaction codes change with every firmware. Probing on a Samsung
tablet showed two traps:

- A first read with a buggy dex decoder (encoded `VALUE_NULL` /
  `VALUE_BOOLEAN` have no payload bytes) shifted every later field and
  produced codes of unrelated methods.
- A binder call with too *few* arguments still runs, with the missing values
  read as zeros; only extra data is rejected. A probe of master mute with one
  argument muted the device for a few seconds. A wrong code with the right
  arity would silently call some other method.

## Decision

- Never hardcode codes. On the first status for a build fingerprint,
  `device-volume.sh` pulls `/system/framework/framework.jar` and
  `audio-codes.py` reads the `TRANSACTION_*` static values of
  `android.media.IAudioService$Stub` from its dex files. The result is cached
  in `$XDG_CACHE_HOME/omadroid/audio-codes/`, keyed by a hash of the
  fingerprint; failures are not cached.
- The parser refuses any table it can't fully check: every field must decode
  as an int, the codes must be exactly 1..N, the interface descriptor must
  match, and each wanted method's proxy must have exactly the expected
  signature (overloads are dropped).
- Before every use, in the same `adb shell`, the device is asked for the media
  volume through the cached `getStreamVolume` code and through
  `cmd audio get-stream-volume`. If they differ, nothing is called, writes
  exit 6, and the Sound tab hides per-app volume and Mute all.
- Phones without the codes (or without Python 3 on the host) mute apps through
  the `PLAY_AUDIO` app op instead.

## Consequences

- Per-app volume works on Samsung firmware without a per-model table, and a
  firmware update re-reads the codes on its own.
- The first status for a firmware copies about 50 MB and takes a few seconds.
- Python 3 (standard library only) is needed for these controls.
- `tests/audio-codes.sh` builds fixture dex files (`tests/make-audio-dex.py`),
  including the decoder regression, an overloaded method and a table with a
  gap, which must be refused; `tests/device-volume.sh` checks that codes that
  don't verify are never used.
