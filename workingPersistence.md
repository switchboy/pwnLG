# Working persistence — confirmed

**Verified 2026-10-28 after full reboot** (Dev Mode app uninstalled, Quick Start+ off):
- `root` SSH on port 22 works (Homebrew Channel SSH server, started automatically at
  boot by the startup hook → proof the hook runs).
- `id` → uid=0(root) groups=0(root),10(wheel),506(pulse-access),509(se),777(crashd)
- `/var/luna/preferences/devmode_enabled` = directory (root-owned) survives reboot
- `/var/lib/webosbrew/startup.sh` (root-owned, mode 755) + `/var/lib/webosbrew/init.d/` exist
- Homebrew Channel reports root status ok

Mechanism: Homebrew Channel elevated service + startup hook + permanent devmode marker.
Access: SSH port 22, root, password `alpine` (no authorized_keys installed; LAN-only risk accepted).

Rollback note: uninstalling Homebrew Channel removes root; `rm -rf /var/lib/webosbrew`
+ `rm -rf /var/luna/preferences/devmode_enabled` cleans hooks.
