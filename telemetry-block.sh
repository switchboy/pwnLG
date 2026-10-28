#!/bin/bash
# pwnLG: neutralize LG telemetry + ad overlays (bind-mount based, re-applied every boot)
# Installed as /var/lib/webosbrew/init.d/10-telemetry-block.sh (root-owned)
# Reversible: reboot removes bind mounts; uninstalling hook restores everything.

LOG=/tmp/telemetry-block.log
exec >>"$LOG" 2>&1
echo "=== telemetry-block starting $(date -u) ==="

# Prepare blocking artifacts in tmpfs
mkdir -p /tmp/.unwritable
touch /tmp/.nullfile

# 1) Stop upload/logging/voice-collection daemons and block their binaries,
#    so systemd cannot respawn them later this boot.
for bin in remotelogger uploadd voiceinput voiceconductor faultmanager; do
  systemctl stop "$bin" 2>/dev/null || killall "$bin" 2>/dev/null
  systemctl mask "$bin" 2>/dev/null   # fails on ro /etc; harmless
  for path in "/usr/sbin/$bin" "/usr/bin/$bin"; do
    if [ -e "$path" ] && ! grep -q " $path " /proc/mounts; then
      mount --bind /tmp/.nullfile "$path" && echo "blocked binary: $path"
    fi
  done
done

# 2) Prevent ACR (Automatic Content Recognition) + ad overlay apps from launching
#    by bind-mounting an empty directory over each app dir.
for app in com.webos.app.acrcomponent com.webos.app.acroverlay \
           com.webos.app.acrhdmi1 com.webos.app.acrhdmi2 com.webos.app.acrhdmi3 com.webos.app.acrhdmi4 \
           com.webos.app.adoverlay com.webos.app.adoverlayex \
           com.webos.app.adhdmi1 com.webos.app.adhdmi2 com.webos.app.adhdmi3 com.webos.app.adhdmi4 \
           com.webos.app.care365 com.webos.app.dangbei-card com.webos.app.dangbei-overlay \
           com.webos.app.voice; do
  dir="/usr/palm/applications/$app"
  if [ -d "$dir" ] && ! mountpoint -q "$dir" 2>/dev/null; then
    mount --bind /tmp/.unwritable "$dir" && echo "blocked app: $app"
  fi
done

# 4b) Home-screen slop: content/ad hubs, sports/weather widgets, assistant UI,
#     LG remote management, update UI, demo/example junk apps. Kept deliberately:
#     home dashboard, livetv/tuner, HDMI inputs, browsers, store, screensaver
#     (OLED burn-in protection), notificationcenter, magicnum, homeconnect.
for app in com.webos.app.premium com.webos.app.livedmost \
           com.webos.app.sportsteamsettings com.webos.app.weatherlocation \
           com.webos.app.softwareupdate com.webos.app.remoteservice \
           com.webos.app.remotesetting com.webos.app.store-demo \
           com.webos.app.sync-demo com.webos.app.google.assistant \
           google.assistant amazon.alexa.view amazon.alexapr \
           com.webos.app.voiceagent com.webos.app.voiceweb \
           com.webos.exampleapp.enyoapp.epg com.webos.exampleapp.groupowner \
           com.webos.exampleapp.nav com.webos.exampleapp.systemui \
           com.webos.exampleapp.videocapture com.webos.exampleapp.qmlapp.discover \
           com.webos.exampleapp.qmlapp.epg com.webos.exampleapp.qmlapp.hbbtv \
           com.webos.exampleapp.qmlapp.livetv com.webos.exampleapp.qmlapp.search \
           com.webos.exampleapp.qmlapp.client.negative.one \
           com.webos.exampleapp.qmlapp.client.negative.two \
           com.webos.exampleapp.qmlapp.client.positive.one \
           com.webos.exampleapp.qmlapp.client.positive.two; do
  dir="/usr/palm/applications/$app"
  if [ -d "$dir" ] && ! grep -q " $dir " /proc/mounts; then
    mount --bind /tmp/.unwritable "$dir" && echo "blocked app: $app"
  fi
done

# 4c) Telemetry/exploit services: bind-empty their service dirs.
#     jsservicelauncher = the jsserver exploit launcher -> closing it removes
#     the attack surface. sportsalert/membership/assetmanager feed home-screen
#     cards & ad assets; care365 service dirs collect usage data.
for svc in com.webos.service.sportsalert com.webos.service.membership \
           com.webos.service.assetmanager com.webos.app.care365 \
           com.webos.app.care365.service jsservicelauncher; do
  dir="/usr/palm/services/$svc"
  if [ -d "$dir" ] && ! grep -q " $dir " /proc/mounts; then
    mount --bind /tmp/.unwritable "$dir" && echo "blocked service: $svc"
  fi
done

# 4d) Store-partition content-discovery engine (CDP = home-screen recommendation
#     cards / ad discovery). The user's real store apps (Netflix etc.) stay.
for cdir in cdp-30; do
  dir="/media/cryptofs/apps/usr/palm/applications/$cdir"
  if [ -d "$dir" ] && ! grep -q " $dir " /proc/mounts; then
    mount --bind /tmp/.unwritable "$dir" && echo "blocked store app: $cdir"
  fi
done

# 5) Wipe ACR consent/state flags (persists — ext4 preferences partition is writable)
rm -f /var/luna/preferences/ACR_Launched /var/luna/preferences/FirstPOPUPACR
echo "cleared ACR flags"

# 6) Extend update/ad domain blocklist (startup.sh already bind-mounts /tmp/hosts
#    onto /etc/hosts and blocks snu/su/su-dev/su-ssl; add remaining LG update hosts)
grep -q 'nsu.lge.com' /etc/hosts 2>/dev/null || {
  echo '127.0.0.1 snu-dev.lge.com nsu.lge.com snu-ssl.lge.com' >> /etc/hosts
  echo '::1 snu-dev.lge.com nsu.lge.com snu-ssl.lge.com' >> /etc/hosts
  echo "extended hosts blocklist"
}

echo "=== telemetry-block done ==="
