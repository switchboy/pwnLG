# Persistent-root attempts log

## Attempt 1 — SlopBro → Homebrew Channel startup hook (current, in progress)
Exploit: jsserver vuln (slopbro). Persistence chain:
1. Payload (root) installs Homebrew Channel IPK via `luna://com.webos.appInstallService/dev/install`.
2. `elevate-service` (from hbchannel service dir) elevates Homebrew Channel to root.
3. Homebrew Channel installs `/var/lib/webosbrew/startup.sh` (root startup hook run early at boot).
4. `devmode_enabled` converted to a directory → dev-mode apps not wiped/expired.
5. `start-devmode.sh` renamed if signature invalid → prevents `/media/developer` wipe.

Rollback if failed: remove `/tmp/autoroot*` dirs; nothing else changed unless payload ran.

Notes / constraints (from community docs):
- Uninstall LG Developer Mode app BEFORE rebooting; never reinstall while rooted.
- Quick Start+ must be disabled for a real reboot.
- To block OTA updates fully, also block at router level:
  snu.lge.com, su.lge.com, su-ssl.lge.com, snu-dev.lge.com, su-dev.lge.com, nsu.lge.com.

## Verification (once root available)
- `id` over hbchannel SSH (root, password `alpine` unless key installed)
- Homebrew Channel "Root status: ok" on TV after reboot
- startup.sh survives reboot: touch marker file at boot, check after power cycle.

## Results
- **2026-10-28 attempt 1: SUCCESS.** Payload ran as root; `devmode_enabled` converted to
  directory; Homebrew Channel 0.7.3 installed + elevated; TV reports Root status OK;
  auto-updates disabled via Homebrew Channel settings.
- Root SSH access prepared: Homebrew SSH server enabled + RSA public key
  (from Dev Manager key `<devman-ssh-key>`) pasted into Homebrew SSH key setting.
- Pending: reboot persistence verification (see below).
