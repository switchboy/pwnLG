#!/bin/sh
# pwnLG block script — runs on the TV as root (installed as /var/lib/webosbrew/init.d/10-pwnpatch)
# Re-applied every boot via bind mounts; nothing is written to system partitions.
# Flags choose what to block; run without flags = block nothing except the always-on bits.
#   --spy        upload/spyware daemons + care365 usage collection
#   --voice      microphone collection pipeline (breaks LG voice control & Alexa voice!)
#   --acr        Automatic Content Recognition ("what are you watching") apps
#   --ads        ad overlays (liveTV/HDMI/home) + dangbei ad framework
#   --slop       home-screen slop: content hubs, recommendations, sports, weather, membership
#   --remotesvc  LG remote support/diagnostic channels
#   --updui      software-update screens/nags (update servers are blocked anyway)
#   --assist     Google Assistant / Alexa UI apps
#   --junk       LG demo + example/test apps
#   --screensaver  (default OFF: keep! protects OLED from burn-in)
#   --notify     (default OFF: keep! Homebrew/system alerts)
#   --account    (default OFF: keep! LG account sign-in)
# Always-on: LG update/ad domain hosts blocklist, jsservicelauncher (exploit service) lockdown.

LOG=/tmp/pwnblock.log
exec >>"$LOG" 2>&1
echo "=== pwnblock starting $(date -u) flags: $* ==="

SPY=0; VOICE=0; ACR=0; ADS=0; SLOP=0; REMOTESVC=0; UPDUI=0; ASSIST=0; JUNK=0
SCREENSAVER=0; NOTIFY=0; ACCOUNT=0
for f in "$@"; do
  case "$f" in
    --spy) SPY=1;; --voice) VOICE=1;; --acr) ACR=1;; --ads) ADS=1;;
    --slop) SLOP=1;; --remotesvc) REMOTESVC=1;; --updui) UPDUI=1;;
    --assist) ASSIST=1;; --junk) JUNK=1;;
    --screensaver) SCREENSAVER=1;; --notify) NOTIFY=1;; --account) ACCOUNT=1;;
  esac
done

mkdir -p /tmp/.unwritable
touch /tmp/.nullfile

# 1) Daemons: stop + bind-block the binary (empty tmpfs file) so systemd
#    cannot respawn them until next reboot.
if [ "$SPY" -eq 1 ]; then
  for bin in remotelogger uploadd faultmanager; do
    systemctl stop "$bin" 2>/dev/null || killall "$bin" 2>/dev/null
    systemctl mask "$bin" 2>/dev/null
    for path in "/usr/sbin/$bin" "/usr/bin/$bin"; do
      if [ -e "$path" ] && ! grep -q " $path " /proc/mounts; then
        mount --bind /tmp/.nullfile "$path" && echo "blocked binary: $path"
      fi
    done
  done
fi
if [ "$VOICE" -eq 1 ]; then
  for bin in voiceinput voiceconductor; do
    systemctl stop "$bin" 2>/dev/null || killall "$bin" 2>/dev/null
    systemctl mask "$bin" 2>/dev/null
    for path in "/usr/sbin/$bin" "/usr/bin/$bin"; do
      if [ -e "$path" ] && ! grep -q " $path " /proc/mounts; then
        mount --bind /tmp/.nullfile "$path" && echo "blocked binary: $path"
      fi
    done
  done
fi

# 2) Apps: bind-mount an empty directory over the app folder -> app cannot start.
block_apps() {
  for app in "$@"; do
    dir="/usr/palm/applications/$app"
    if [ -d "$dir" ] && ! grep -q " $dir " /proc/mounts; then
      mount --bind /tmp/.unwritable "$dir" && echo "blocked app: $app"
    fi
  done
}
block_svcs() {
  for svc in "$@"; do
    dir="/usr/palm/services/$svc"
    if [ -d "$dir" ] && ! grep -q " $dir " /proc/mounts; then
      mount --bind /tmp/.unwritable "$dir" && echo "blocked service: $svc"
    fi
  done
}

if [ "$VOICE" -eq 1 ]; then
  block_apps com.webos.app.voice
fi
if [ "$ACR" -eq 1 ]; then
  block_apps com.webos.app.acrcomponent com.webos.app.acroverlay \
    com.webos.app.acrhdmi1 com.webos.app.acrhdmi2 com.webos.app.acrhdmi3 com.webos.app.acrhdmi4
  rm -f /var/luna/preferences/ACR_Launched /var/luna/preferences/FirstPOPUPACR
  echo "cleared ACR flags"
fi
if [ "$ADS" -eq 1 ]; then
  block_apps com.webos.app.adoverlay com.webos.app.adoverlayex \
    com.webos.app.adhdmi1 com.webos.app.adhdmi2 com.webos.app.adhdmi3 com.webos.app.adhdmi4 \
    com.webos.app.dangbei-card com.webos.app.dangbei-overlay
fi
if [ "$SLOP" -eq 1 ]; then
  block_apps com.webos.app.premium com.webos.app.livedmost \
    com.webos.app.sportsteamsettings com.webos.app.weatherlocation
  block_svcs com.webos.service.sportsalert com.webos.service.membership com.webos.service.assetmanager
  dir="/media/cryptofs/apps/usr/palm/applications/cdp-30"
  if [ -d "$dir" ] && ! grep -q " $dir " /proc/mounts; then
    mount --bind /tmp/.unwritable "$dir" && echo "blocked store app: cdp-30"
  fi
fi
if [ "$SPY" -eq 1 ]; then
  block_apps com.webos.app.care365
  block_svcs com.webos.app.care365 com.webos.app.care365.service
fi
if [ "$REMOTESVC" -eq 1 ]; then
  block_apps com.webos.app.remoteservice com.webos.app.remotesetting
fi
if [ "$UPDUI" -eq 1 ]; then
  block_apps com.webos.app.softwareupdate
fi
if [ "$ASSIST" -eq 1 ]; then
  block_apps google.assistant amazon.alexa.view amazon.alexapr \
    com.webos.app.voiceagent com.webos.app.voiceweb
fi
if [ "$JUNK" -eq 1 ]; then
  block_apps com.webos.app.store-demo com.webos.app.sync-demo \
    com.webos.exampleapp.enyoapp.epg com.webos.exampleapp.groupowner \
    com.webos.exampleapp.nav com.webos.exampleapp.systemui \
    com.webos.exampleapp.videocapture com.webos.exampleapp.qmlapp.discover \
    com.webos.exampleapp.qmlapp.epg com.webos.exampleapp.qmlapp.hbbtv \
    com.webos.exampleapp.qmlapp.livetv com.webos.exampleapp.qmlapp.search \
    com.webos.exampleapp.qmlapp.client.negative.one \
    com.webos.exampleapp.qmlapp.client.negative.two \
    com.webos.exampleapp.qmlapp.client.positive.one \
    com.webos.exampleapp.qmlapp.client.positive.two
fi

if [ "$SCREENSAVER" -eq 1 ]; then
  block_apps com.webos.app.screensaver   # CAUTION: removes OLED burn-in protection!
fi
if [ "$NOTIFY" -eq 1 ]; then
  block_apps com.webos.app.notificationcenter
fi
if [ "$ACCOUNT" -eq 1 ]; then
  block_apps com.webos.app.homeconnect
fi

# 3) Security lockdown: close the jsserver exploit service (always).
block_svcs jsservicelauncher

# 4) Hosts blocklist: LG update/ad endpoints resolve to localhost.
#    Homebrew startup.sh bind-mounts a fresh /tmp/hosts onto /etc/hosts each boot.
grep -q 'nsu.lge.com' /etc/hosts 2>/dev/null || {
  echo '127.0.0.1 snu.lge.com su.lge.com su-ssl.lge.com su-dev.lge.com snu-dev.lge.com snu-ssl.lge.com nsu.lge.com' >> /etc/hosts
  echo '::1 snu.lge.com su.lge.com su-ssl.lge.com su-dev.lge.com snu-dev.lge.com snu-ssl.lge.com nsu.lge.com' >> /etc/hosts
  echo "hosts blocklist applied"
}

echo "=== pwnblock done ==="
