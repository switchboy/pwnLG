# Successful telemetry removal — CONFIRMED (survives reboot)

## Procedure
1. Root via SlopBro (see `wayToPwnLG.md`); Homebrew Channel elevated, its
   `startup.sh` hook installed at `/var/lib/webosbrew/startup.sh`.
   Homebrew's hook already neuters upload spools (`/tmp/rdxd`, `/tmp/uploadd`,
   `/var/spool/uploadd/*` bind-mounted read-only) and blocks update domains.
2. Our additional hook: `/var/lib/webosbrew/init.d/10-telemetry-block`
   (root-owned, mode 755; script source kept as `telemetry-block.sh`).
   IMPORTANT: run-parts ignores filenames containing a DOT — keep the hook
   name dot-free (`10-telemetry-block`, not `10-telemetry-block.sh`).
3. The hook, at every boot:
   - `systemctl stop` + bind-mounts an empty tmpfs file over binaries:
     `remotelogger`, `uploadd`, `voiceinput`, `voiceconductor`, `faultmanager`
     → daemons dead and cannot respawn (systemd restarts fail on blocked binary).
   - Bind-mounts an empty dir over ACR/ad/data-collection apps:
     `com.webos.app.acrcomponent`, `acroverlay`, `acrhdmi1-4`,
     `adoverlay`, `adoverlayex`, `adhdmi1-4`, `care365`,
     `dangbei-card`, `dangbei-overlay`, `com.webos.app.voice`.
   - Deletes persistent ACR consent flags
     (`/var/luna/preferences/ACR_Launched`, `FirstPOPUPACR`).
   - Appends `snu-dev.lge.com`, `nsu.lge.com`, `snu-ssl.lge.com` to the
     boot-regenerated `/etc/hosts` blocklist (bind-mounted by startup.sh).

## Verified after reboot (2026-10-28)
- `/tmp/telemetry-block.log` regenerated at boot → hook ran ✓
- `systemctl is-active` → inactive/failed for all 5 telemetry units; 0 matching processes
- 16 app dirs bind-blocked; ACR flags gone; hosts entries present
- `crashd` intentionally left running (local crash dumps only; upload path dead)

## Side effects
- Voice control (LG assistant + Alexa voice input) is dead — mic capture disabled by design.
- Ad overlays never launch (see `successfulAdRemoval.md`).
- Rollback: reboot clears bind mounts; delete the init.d hook to restore permanently.
