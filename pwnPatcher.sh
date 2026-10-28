#!/usr/bin/env bash
# pwnPatcher — one-click LG webOS TV patcher (Linux/macOS terminal)
# From "Developer Mode app installed" to "rooted, spyware/ads blocked, updates disabled".
# Companion files (keep in same folder): pwnblock.sh pwnpatch.sh pwnreboot.sh
set -uo pipefail

G=$'\033[1;32m'; R=$'\033[1;31m'; Y=$'\033[1;33m'; B=$'\033[1;36m'; N=$'\033[0m'; DIM=$'\033[2m'
say()  { printf '%s\n' "$1"; }
ok()   { printf '%sOK:%s %s\n' "$G" "$N" "$1"; }
warn() { printf '%sWARN:%s %s\n' "$Y" "$N" "$1"; }
err()  { printf '%sERROR:%s %s\n' "$R" "$N" "$1"; }
info() { printf '%s-->%s %s\n' "$B" "$N" "$1"; }

say "${B}=============================================================${N}"
say "${B}  pwnPatcher v1.0 — take back your LG webOS TV (rooted, spy-free)${N}"
say "${B}=============================================================${N}"
say "${Y}Safety:${N} never write to system partitions (kernel/rootfs/tvservice) — bricks the TV."
say "This patcher only uses userspace tricks (bind mounts + startup hooks). Reversible."
say "${DIM}You need: the TV's IP + the 6-char passphrase shown in the Developer Mode app.${N}"
say ""

# ---- prerequisites ----------------------------------------------------------
for tool in ssh scp curl python3 ssh-keygen; do
  command -v "$tool" >/dev/null 2>&1 || { err "Missing tool: $tool (see pwnPatchGuide.md)"; exit 1; }
done
command -v git >/dev/null 2>/dev/null && HAVE_GIT=1 || HAVE_GIT=0

TV_IP=""
while true; do
  read -r -p "TV IP address [192.168.1.119]: " TV_IP
  TV_IP=${TV_IP:-192.168.1.119}
  case "$TV_IP" in *.*.*.*) break ;; *) say "That doesn't look like an IP. Try again." ;; esac
done
say "${Y}Make sure:${N} Developer Mode app installed + Dev Mode Status = ON, and"
say "  'Key Server' is enabled in the app (needed once, to fetch the SSH key)."
read -r -p "6-char passphrase from the Developer Mode app (case-sensitive): " PIN
say ""

SSHOPTS="-p 9922 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8"
if command -v sshpass >/dev/null 2>&1; then
  PFX="sshpass -p $PIN "   # auto-supplies the key passphrase -> no typing
else
  PFX=""                   # you'll be asked to type the passphrase a few times
fi
devssh() { ${PFX}ssh $SSHOPTS -i ./webos_rsa prisoner@"$TV_IP" "$1"; }
rootssh() { ssh -p 22 -i ./pwn_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@"$TV_IP" "$1"; }

# ---- fetch SSH key ----------------------------------------------------------
info "Fetching SSH key from the TV (port 9991) ..."
if ! curl -f -s -m 10 "http://${TV_IP}:9991/webos_rsa" -o webos_rsa; then
  err "Could not fetch webos_rsa. Enable 'Key Server' in the Developer Mode app and retry."
  exit 1
fi
chmod 600 webos_rsa
ok "SSH key downloaded."

# ---- device info ------------------------------------------------------------
info "Reading TV info ..."
DEVINFO=$(devssh 'cat /var/run/nyx/device_info.json' 2>/dev/null)
OSINFO=$(devssh 'cat /var/run/nyx/os_info.json' 2>/dev/null)
OTAID=$(printf '%s' "$DEVINFO" | grep -o '"hardware_id": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
FW=$(printf '%s' "$OSINFO" | grep -o '"webos_manufacturing_version": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
MAJOR=$(printf '%s' "$OSINFO" | grep -o '"core_os_release": *"[0-9]*' | tr -d '"' | cut -d. -f1)
MODEL=$(printf '%s' "$DEVINFO" | grep -o '"product_id": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
if [ -z "$OTAID" ]; then
  err "Could not read TV info. Is Dev Mode ON and SSH reachable? (see guide troubleshooting)"
  exit 1
fi
ok "Model: ${MODEL:-unknown} | OTAID: ${OTAID} | firmware: ${FW:-?} | webOS major: ${MAJOR:-?}"
say "${DIM}Exploit check: https://cani.rootmy.tv/ (SlopBro covers webOS 4-11 unless very new patched builds).${N}"
say ""

# ---- what to keep/remove ----------------------------------------------------
say "${Y}Pick what to block (Enter = default in brackets):${N}"
ask() { # ask <var> <default> <question+description>
  local def="$2" q="$3" ans
  read -r -p "$q [$def]: " ans
  ans=${ans:-$def}
  case "$ans" in [yY]*) ans=y ;; *) ans=n ;; esac
  eval "$1=$ans"
}
ask KEEP_SPY   y "Block SPYWARE upload daemons? [uploadd/remotelogger/faultmanager upload, care365 usage collection]"
ask KEEP_VOICE n "Block VOICE eavesdropping? (voiceinput/voiceconductor/voice apps — LG voice control & Alexa voice will stop working)"
ask KEEP_ACR   y "Block CONTENT RECOGNITION (ACR)? (tracks what you watch, incl. HDMI sources)"
ask KEEP_ADS   y "Block AD OVERLAYS? (ads on live TV, home screen and HDMI inputs + dangbei ad framework)"
ask KEEP_SLOP  y "Block HOME-SCREEN SLOP? (recommendations engine cdp-30, premium/livedmost hubs, sports alerts, weather widget, membership, ad asset service)"
ask KEEP_REMOTESVC y "Block LG REMOTE SUPPORT channels? (remoteservice/remotesetting — LG partner/diagnostic remote control)"
ask KEEP_UPDUI y "Block LG UPDATE SCREENS? (update UI — update servers get blocked either way)"
ask KEEP_ASSIST y "Block VOICE ASSISTANT UI? (Google Assistant / Alexa apps — voice is dead if you blocked voice eavesdropping anyway)"
ask KEEP_JUNK  y "Block LG DEMO/EXAMPLE junk apps? (store-demo, sync-demo, exampleapp.* test apps)"
ask KEEP_SCREENSAVER n "Block SCREEN SAVER? (NOT recommended — protects your OLED panel from burn-in)"
ask KEEP_NOTIFY n "Block NOTIFICATION CENTER? (not recommended — keeps Homebrew alerts visible)"
ask KEEP_ACCOUNT n "Block LG ACCOUNT (homeconnect)? (only pick y if you never use LG account features)"
say ""

FLAGS=""
[ "$KEEP_SPY" = y ]        && FLAGS="$FLAGS --spy"
[ "$KEEP_VOICE" = y ]      && FLAGS="$FLAGS --voice"
[ "$KEEP_ACR" = y ]        && FLAGS="$FLAGS --acr"
[ "$KEEP_ADS" = y ]        && FLAGS="$FLAGS --ads"
[ "$KEEP_SLOP" = y ]       && FLAGS="$FLAGS --slop"
[ "$KEEP_REMOTESVC" = y ]  && FLAGS="$FLAGS --remotesvc"
[ "$KEEP_UPDUI" = y ]      && FLAGS="$FLAGS --updui"
[ "$KEEP_ASSIST" = y ]     && FLAGS="$FLAGS --assist"
[ "$KEEP_JUNK" = y ]       && FLAGS="$FLAGS --junk"
[ "$KEEP_SCREENSAVER" = y ] && FLAGS="$FLAGS --screensaver"
[ "$KEEP_NOTIFY" = y ]      && FLAGS="$FLAGS --notify"
[ "$KEEP_ACCOUNT" = y ]     && FLAGS="$FLAGS --account"
say "Selected flags:${FLAGS:- (nothing extra — only always-on protections)}"
say ""

# ---- firewall ---------------------------------------------------------------
FW_DISABLED=0
FW_ACTIVE=0
if command -v ufw >/dev/null 2>&1; then
  if systemctl is-active ufw 2>/dev/null | grep -q '^active' || ufw status 2>/dev/null | grep -q "Status: active"; then
    FW_ACTIVE=1
  fi
fi
if [ "$FW_ACTIVE" = 1 ]; then
  warn "Your firewall (ufw) is ON. The TV must reach your PC during the exploit."
  read -r -p "Disable it for the patch run? (sudo; re-enabled after) [Y/n]: " fwans
  case "${fwans:-y}" in
    [yY]*) sudo ufw disable && FW_DISABLED=1 ;;
    *) warn "Firewall stays ON — if the exploit page never loads, this is why." ;;
  esac
fi

# ---- get the exploit --------------------------------------------------------
if [ ! -f slopbro/slopbro.py ]; then
  info "Downloading SlopBro exploit ..."
  if [ "$HAVE_GIT" = 1 ] && git clone -q https://github.com/throwaway96/slopbro.git slopbro 2>/dev/null; then
    :
  else
    curl -f -L -s -m 30 -o slopbro.zip https://github.com/throwaway96/slopbro/archive/refs/heads/main.zip || {
      err "Download failed (internet? GitHub reachable?)."; exit 1; }
    python3 -c "import zipfile,shutil,os
zipfile.ZipFile('slopbro.zip').extractall('.')
if os.path.isdir('slopbro'): shutil.rmtree('slopbro')
os.rename('slopbro-main','slopbro')" || { err "Could not unpack slopbro.zip"; exit 1; }
  fi
fi
ok "SlopBro ready."

# ---- run the exploit --------------------------------------------------------
say ""
say "${Y}TV-side:${N} close ALL apps (e.g. Plex) so the TV sits idle on the home screen."
say "During the run a PAIRING prompt appears on the TV — accept it with the remote."
say "Then the TV browser loads the exploit page from your PC; watch for toasts."
say ""
LOCAL_IP=$(ip route get "$TV_IP" 2>/dev/null | grep -oE 'src +[0-9.]+' | awk '{print $2}' | head -1)
LIP_OPT=""; [ -n "$LOCAL_IP" ] && LIP_OPT="--local-ip $LOCAL_IP"
info "Running exploit (webOS $MAJOR) ..."
python3 slopbro/slopbro.py --debug --webos-version "$MAJOR" $LIP_OPT "$TV_IP" || {
  err "Exploit did not complete. Check: pairing accepted? firewall? TV idle? firmware vulnerable on cani.rootmy.tv?"
  [ "$FW_DISABLED" = 1 ] && sudo ufw enable
  exit 1
}
ok "Exploit payload delivered. Homebrew Channel is installing (check TV screen/toasts)."

# ---- SSH keypair for passwordless root access -------------------------------
[ -f pwn_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f pwn_ed25519
ok "Generated root SSH key (pwn_ed25519 / pwn_ed25519.pub)."

# ---- push patch files -------------------------------------------------------
info "Pushing patch scripts to the TV ..."
${PFX}ssh $SSHOPTS -i ./webos_rsa prisoner@"$TV_IP" 'cat > /tmp/pwnblock.sh' < pwnblock.sh
${PFX}ssh $SSHOPTS -i ./webos_rsa prisoner@"$TV_IP" 'cat > /tmp/pwnpatch.sh' < pwnpatch.sh
${PFX}ssh $SSHOPTS -i ./webos_rsa prisoner@"$TV_IP" 'cat > /tmp/pwnreboot.sh' < pwnreboot.sh
${PFX}ssh $SSHOPTS -i ./webos_rsa prisoner@"$TV_IP" 'cat > /tmp/pwn_pubkey.txt' < pwn_ed25519.pub
ok "Scripts pushed."

info "Applying patches (root) ..."
out=$(devssh 'sh /tmp/pwnpatch.sh '"$FLAGS" 2>&1)
printf '%s\n' "$out" | grep -q PWN_DONE && ok "Patches applied + root SSH server started (port 22)." \
  || { err "Patch step failed: $out"; exit 1; }

# ---- uninstall Dev Mode app BEFORE reboot -----------------------------------
say ""
say "${Y}GO TO THE TV NOW:${N} open the home menu -> Developer Mode app -> Remove app."
say "The TV must reboot WITHOUT the Dev Mode app installed. Waiting for you..."
tries=0
while true; do
  st=$(rootssh 'ls -d /media/cryptofs/apps/usr/palm/applications/com.palmdts.devmode >/dev/null 2>&1 && echo STILL || echo GONE' 2>/dev/null)
  if printf '%s' "$st" | grep -q GONE; then ok "Developer Mode app removed."; break; fi
  tries=$((tries+1))
  if [ "$tries" -ge 60 ]; then err "Timed out waiting for Dev Mode app removal. Do it manually, then re-run: bash pwnPatcher.sh (safe to re-run)." ; exit 1; fi
  printf '.'
  sleep 5
done
say ""

# ---- reboot -----------------------------------------------------------------
info "Rebooting the TV ..."
rootssh 'sh /tmp/pwnreboot.sh' 2>/dev/null
say "${DIM}Connection dropped during reboot (normal). Waiting ~60s for the TV ...${N}"
sleep 60

# ---- verify -----------------------------------------------------------------
info "Verifying persistent root ..."
uid=$(rootssh 'id' 2>/dev/null | grep -c 'uid=0(root)')
if [ "$uid" -eq 1 ]; then ok "ROOT SSH works: root@${TV_IP} port 22 (key: pwn_ed25519 — no password)."
else err "No root SSH after reboot. Re-run this patcher or check guide troubleshooting."; exit 1; fi
blocks=$(rootssh 'grep -cE "applications/|services/|cryptofs.*cdp|nullfile" /proc/mounts' 2>/dev/null | tr -d ' \n')
procs=$(rootssh 'for p in /proc/[0-9]*/comm; do cat $p; done 2>/dev/null | grep -icE "remotelog|uploadd|voiceinput|voiceconduct|faultmanager|sportsalert|membership|assetmanager"' 2>/dev/null | tr -d ' \n')
say "Blocked mounts: ${blocks:-?} | running spyware/telemetry processes: ${procs:-?}"
say "Homebrew Channel app on the TV shows Root status ok; updates are blocked."

[ "$FW_DISABLED" = 1 ] && { sudo ufw enable; ok "Firewall re-enabled."; }

say ""
say "${G}SUCCESS — your TV is rooted, spyware/ads/update-nags are gone, and it survives reboots.${N}"
say "${Y}Remember:${N}"
say "  * NEVER reinstall the Developer Mode app while rooted (wipes apps)."
say "  * Root shell later:  ssh -p 22 -i pwn_ed25519 root@${TV_IP}"
say "  * Rollback: delete /var/lib/webosbrew/init.d/10-pwnpatch + reboot; uninstall Homebrew Channel."
say "  * Disable Quick Start+ (Settings -> General) if you want power off/on = real reboot."
say "  * Home screen leftovers: long-press cards -> delete; uninstall unwanted store apps."
