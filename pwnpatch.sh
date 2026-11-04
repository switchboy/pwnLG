#!/bin/sh
# pwnLG patch script — elevates from Developer Mode SSH through Homebrew Channel.
# Installs the block hook, enables root SSH + update blocking, installs your SSH key,
# starts the SSH server right away, then runs the block script with your chosen flags.
# Usage: sh /tmp/pwnpatch.sh [--spy --voice --acr --ads --slop --remotesvc --updui --assist --junk]
set -e

# Developer Mode SSH runs as prisoner; execute privileged steps through Homebrew.
if [ "$(id -u)" -ne 0 ]; then
    if [ "${PWNLG_ELEVATED:-0}" = 1 ]; then
        echo "ERROR: Homebrew service did not provide root privileges" >&2
        exit 1
    fi

    remote_command="PWNLG_ELEVATED=1 sh /tmp/pwnpatch.sh"
    for flag in "$@"; do
        case "$flag" in
            --spy|--voice|--acr|--ads|--slop|--remotesvc|--updui|--assist|--junk|--screensaver|--notify|--account)
                remote_command="$remote_command $flag"
                ;;
            *)
                echo "ERROR: Unsupported flag: $flag" >&2
                exit 1
                ;;
        esac
    done

    request=$(printf '{"command":"%s"}' "$remote_command")
    if ! response=$(luna-send-pub -n 1 -f luna://org.webosbrew.hbchannel.service/exec "$request"); then
        echo "ERROR: Homebrew root service unavailable" >&2
        exit 1
    fi
    if ! printf '%s\n' "$response" | grep -Eq '"returnValue"[[:space:]]*:[[:space:]]*true' ||
       ! printf '%s\n' "$response" | grep -Eq '"stdoutString"[[:space:]]*:[[:space:]]*"PWN_DONE'; then
        printf 'ERROR: Homebrew root service failed:\n%s\n' "$response" >&2
        exit 1
    fi

    echo PWN_DONE
    exit 0
fi

SVC=/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service

# Homebrew flags: auto-start root SSH server + block system updates at every boot
touch /var/luna/preferences/webosbrew_sshd_enabled /var/luna/preferences/webosbrew_block_updates
sync -f /var/luna/preferences

# Install SSH key so you never type a password again
mkdir -p /home/root/.ssh && chmod 700 /home/root/.ssh
touch /home/root/.ssh/authorized_keys
grep -qxF "$(cat /tmp/pwn_pubkey.txt)" /home/root/.ssh/authorized_keys || cat /tmp/pwn_pubkey.txt >> /home/root/.ssh/authorized_keys
chmod 600 /home/root/.ssh/authorized_keys
chown root:root /home/root/.ssh/authorized_keys /home/root/.ssh 2>/dev/null || true

# Keep the blocker separate from the boot hook so selected flags persist.
mkdir -p /var/lib/webosbrew/init.d
cp /tmp/pwnblock.sh /var/lib/webosbrew/pwnblock.sh
chown root:root /var/lib/webosbrew/pwnblock.sh 2>/dev/null || true
chmod 700 /var/lib/webosbrew/pwnblock.sh

{
    printf '#!/bin/sh\n'
    printf 'exec sh /var/lib/webosbrew/pwnblock.sh'
    for flag in "$@"; do
        case "$flag" in
            --spy|--voice|--acr|--ads|--slop|--remotesvc|--updui|--assist|--junk|--screensaver|--notify|--account)
                printf ' %s' "$flag"
                ;;
            *)
                echo "ERROR: Unsupported flag: $flag" >&2
                exit 1
                ;;
        esac
    done
    printf '\n'
} > /var/lib/webosbrew/init.d/10-pwnpatch.new
chmod 755 /var/lib/webosbrew/init.d/10-pwnpatch.new
mv -f /var/lib/webosbrew/init.d/10-pwnpatch.new /var/lib/webosbrew/init.d/10-pwnpatch
chown root:root /var/lib/webosbrew/init.d/10-pwnpatch 2>/dev/null || true

# Apply the blocks right now (bind mounts; reboot will re-apply via hook)
sh /tmp/pwnblock.sh "$@"

# Developer Mode SSH uses Dropbear on 9922; detect port 22 instead.
# Dropbear needs a writable host-key directory before its first connection.
mkdir -p /var/lib/webosbrew/sshd
chmod 700 /var/lib/webosbrew/sshd
if ! netstat -lnt 2>/dev/null | grep -Eq ':22[[:space:]]'; then
    "$SVC/bin/dropbear" -R >>/tmp/pwnlg-dropbear.log 2>&1
    sleep 1
fi

# Shout at the TV screen: Dev Mode app must be gone BEFORE any reboot!
/usr/bin/luna-send -n 1 -a com.webos.service.secondscreen.gateway \
  'luna://com.webos.notification/createToast' \
  '{"sourceId":"com.webos.service.secondscreen.gateway","message":"<b>pwnLG</b><br/>Uninstall the Developer Mode app from the home menu NOW.<br/>Never reboot with it installed, and never reinstall it!"}' >/dev/null 2>&1 || true

sync
echo "PWN_DONE"
