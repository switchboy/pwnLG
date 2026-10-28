# Successful ad removal — procedure

Confirmed at process/mount level (2026-10-28, 40 bind-blocks surviving reboot); visual check by user passed for ad overlays.

1. Rooted TV + Homebrew Channel startup hook active (see `workingPersistence.md`).
2. `/var/lib/webosbrew/init.d/10-telemetry-block` bind-mounts an empty
   directory every boot over: ad overlays (adoverlay/ex, adhdmi1-4, dangbei),
   ACR apps, content hubs (premium, livedmost, cdp-30 recommendation engine),
   sports/weather/membership services, voice-assistant UI, LG remote
   management, update UI, demo/example apps — see `removeAdsAttempt.md` for the
   full list and kept-components rationale.
3. Ad content endpoints are unreachable anyway: `snu*.lge.com`/`su*.lge.com`/
   `nsu.lge.com` are blackholed to localhost via boot-regenerated `/etc/hosts`
   (Homebrew Channel "Block system updates" + our extra entries).
4. Personalization source removed: ACR apps blocked + ACR consent flags
   deleted, so ad targeting data no longer exists on the device.

Rollback: delete the init.d hook + reboot → ads return (LG side unchanged).
