# Ad removal attempts

## Attempt 1 — bind-block ad overlay apps (2026-10-28) — WORKING
LG's home-screen/live-TV ads on webOS 5 are rendered by transparent overlay
apps (`com.webos.app.adoverlay`/`adoverlayex` draw into an `acrLayer` window
group attached to `com.webos.app.livetv`; HDMI inputs use `adhdmi1-4`; the
`dangbei-card`/`dangbei-overlay` apps are a third-party ad framework present
in firmware). Ad content itself is fetched from LG update hosts (snu/su —
already blocked by Homebrew Channel's hosts blocklist).

Method (same init.d hook as telemetry, see `telemetry-block.sh`):
- bind-mount empty dir over: adoverlay, adoverlayex, adhdmi1-4,
  dangbei-card, dangbei-overlay (and all ACR apps, which also drive
  personalized ad targeting)
- hosts-block snu/su/snu-dev/snu-ssl/su-dev/nsu.lge.com

Verification: mount count 16 app blocks after reboot; overlay apps never
launch (appinfo.json unreadable → launch fails silently). Visual confirmation
by user requested (home screen + live TV + HDMI inputs).

## Attempt 2 — home-screen slop purge (2026-10-28) — WORKING (40 blocks total)
Added to the same init.d hook:
- content/ad hubs: com.webos.app.premium, livedmost (ACR "most watched"),
  cdp-30 (store-partition content-discovery/recommendation engine)
- sports/weather widgets: com.webos.service.sportsalert, sportsteamsettings,
  weatherlocation; membership service; assetmanager (ad asset service)
- LG remote management telemetry: remoteservice/remotesetting; update UI app
  (softwareupdate); voice-assistant UI (google.assistant, amazon alexa apps,
  voiceagent, voiceweb); demo/example apps (store-demo, sync-demo, exampleapp.*)
- care365 service dirs; jsservicelauncher (the exploit's own service — closing
  it removes the attack surface)
Deliberately KEPT: home dashboard (home/fullhome), liveTV + tuner/channel apps,
HDMI/AV input apps, browsers, store app, screensaver (OLED burn-in protection!),
notificationcenter, magicnum, homeconnect, real user store apps (Netflix etc.).

User-side finishing: remove leftover dashboard cards via long-press/Edit mode;
uninstall unwanted store apps from the Content Store UI.

## Attempt 3 — (spare, if overlays still appear somewhere)
Kill WAM processes rendering ad UI in init.d loop, or bind-block
com.webos.app.homepage variant — not needed so far.
