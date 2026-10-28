# Telemetry removal attempts

## Identified telemetry/monitoring components (from pre-root backup)
From process cmdline dump (backup/process_cmdline.txt) and preferences:

| Component | Role | Notes |
|---|---|---|
| /usr/sbin/uploadd | uploads logs/data to LG | kill candidate |
| /usr/sbin/remotelogger | remote log collection | kill candidate |
| /usr/sbin/voiceinput, /usr/sbin/voiceconductor, com.webos.app.voice | voice capture ("listening TV") | kill breaks voice UX — acceptable |
| /usr/sbin/PmLogDaemon, /usr/sbin/PmKLogDaemon | Palm log daemons feeding syslog | keep (local logging) or redirect |
| activitymanager | app/content usage tracking | kill candidate |
| /usr/sbin/update | OTA updater | disable separately (Step 6) |
| /var/luna/preferences ACR_Launched, FirstPOPUPACR | Automatic Content Recognition flags | clear/block once root available |
| /usr/sbin/crashd + /usr/sbin/faultmanager | crash reporting (may upload) | check upload behaviour |

## Strategy (once root via Homebrew Channel)
1. Enumerate all root-owned services + Luna services dirs (system apps list was
   empty in dev-mode jail view; needs root).
2. Prefer Homebrew Channel startup hook: /var/lib/webosbrew/startup.sh runs as
   root at boot → add kill/pkill lines + ACR flag wipe + DNS block hosts file.
3. Also block update domains (Step 6 overlap): snu.lge.com, su.lge.com,
   su-ssl.lge.com, snu-dev.lge.com, su-dev.lge.com, nsu.lge.com.
4. Verify survival across reboot; roll back anything that breaks boot.

## Attempt log
### Attempt 1 — init.d bind-mount hook (2026-10-28): SUCCESS
- Installed hook, ran live: all telemetry units inactive, 0 processes, 22 blocks applied.
- First reboot persistence FAILED: busybox `run-parts` skips filenames containing
  dots (`10-telemetry-block.sh` ignored). Renamed to `10-telemetry-block` (dot-free).
- Second reboot: hook ran at boot (log regenerated), telemetry stays dead ✓
  Full details: `successfulTelemetryRemoval.md`.
