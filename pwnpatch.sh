#!/bin/sh
# pwnLG patch script — runs once on the TV as root (via dev-mode SSH).
# Installs the block hook, enables root SSH + update blocking, installs your SSH key,
# starts the SSH server right away, then runs the block script with your chosen flags.
# Usage: sh /tmp/pwnpatch.sh [--spy --voice --acr --ads --slop --remotesvc --updui --assist --junk]
set -e

SVC=/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service

# Homebrew flags: auto-start root SSH server + block system updates at every boot
touch /var/luna/preferences/webosbrew_sshd_enabled /var/luna/preferences/webosbrew_block_updates
sync -f /var/luna/preferences

# Install SSH key so you never type a password again
mkdir -p /home/root/.ssh && chmod 700 /home/root/.ssh
cat /tmp/pwn_pubkey.txt >> /home/root/.ssh/authorized_keys
chmod 600 /home/root/.ssh/authorized_keys
chown root:root /home/root/.ssh/authorized_keys /home/root/.ssh 2>/dev/null || true

# Install the block hook (NOTE: name must have NO DOT — busybox run-parts skips dots!)
mkdir -p /var/lib/webosbrew/init.d
cp /tmp/pwnblock.sh /var/lib/webosbrew/init.d/10-pwnpatch
chown root:root /var/lib/webosbrew/init.d/10-pwnpatch 2>/dev/null || true
chmod 755 /var/lib/webosbrew/init.d/10-pwnpatch

# Apply the blocks right now (bind mounts; reboot will re-apply via hook)
sh /tmp/pwnblock.sh "$@"

# Start root SSH server immediately (dropbear from Homebrew Channel binaries)
pgrep dropbear >/dev/null 2>&1 || { "$SVC/bin/dropbear" -R >/dev/null 2>&1 & sleep 1; }

# Shout at the TV screen: Dev Mode app must be gone BEFORE any reboot!
/usr/bin/luna-send -n 1 -a com.webos.service.secondscreen.gateway \
  'luna://com.webos.notification/createToast' \
  '{"sourceId":"com.webos.service.secondscreen.gateway","message":"<b>pwnLG</b><br/>Uninstall the Developer Mode app from the home menu NOW.<br/>Never reboot with it installed, and never reinstall it!"}' >/dev/null 2>&1 || true

sync
echo "PWN_DONE"
