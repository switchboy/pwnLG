# wayToPwnLG — Rooting an LG webOS TV & stripping telemetry/ads (consumer-owned device)

> **Legal note:** This targets hardware you bought and paid for. Removing
> telemetry/telemetry-uploads from your own device is a consumer action; in the
> EU it sits squarely in the spirit of GDPR/GD "consent must be freely given".
> You do this at your own risk.
>
> **Hardware warning:** NEVER write to system partitions (kernel, rootfs,
> tvservice). A botched write bricks the TV permanently, not recoverable by a
> factory reset. See https://rootmy.tv/warning . Everything below uses
> userspace-only, reversible mechanisms.

## 0. What this covers
Rooting webOS 4–11 TVs with the **SlopBro** exploit (jsserver vulnerability),
installing Homebrew Channel, persistent root, telemetry/ACR/voice-collection
blocking, ad-overlay blocking, OTA-update blocking. Tested on an OLED55CX
(2020, webOS 5.6.2, fw 04.64.00).

> **Noob shortcut:** use `pwnPatcher.sh` (Linux/macOS) or `pwnPatcher.bat`
> (Windows) + `pwnPatchGuide.md` in this repo — one interactive script does
> everything below with selectable blocking options.

## 1. Enable Developer Mode + shell access
1. Install "Developer Mode" app from the LG Content Store, set Dev Mode ON, reboot.
2. Note the 6-char passphrase shown in the app.
3. Get the SSH key: enable "Key Server" in the app, then fetch
   `http://<TV-IP>:9991/webos_rsa` (passphrase = the 6-char string).
   Or use webOS Dev Manager (webosbrew/dev-manager-desktop), which stores it.
4. Connect (modern OpenSSH needs legacy-algorithm flags; the TV's sshd offers
   only `ssh-rsa` host keys):
   ```sh
   ssh -p 9922 -i webos_rsa \
     -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa \
     prisoner@<TV-IP>
   ```
   You land in a restricted userspace shell (`prisoner`). Read-only `nosuid`
   mounts mean there is no SUID privilege escalation on modern firmware.

## 2. Check your firmware is exploitable
Get your OTAID (no root needed!):
```sh
cat /var/run/nyx/device_info.json   # hardware_id field, e.g. HE_DTV_W20O_AFABABAA
cat /var/run/nyx/os_info.json       # webos_manufacturing_version, e.g. 04.64.00
```
Look these up on **https://cani.rootmy.tv/**. On recent patched firmware the
older exploits (crashd, faultmanager, WTA, dejavuln, RootMyTV) are dead —
**SlopBro** (https://github.com/throwaway96/slopbro) still covers webOS 4–11
including current LG patch workarounds.

## 3. Root with SlopBro
On your PC (Python 3):
```sh
git clone https://github.com/throwaway96/slopbro.git
cd slopbro
python3 slopbro.py --debug --webos-version <major> <TV-IP>
```
- A pairing prompt appears on the TV → accept it (first time only).
- The TV browser loads an exploit page from your PC's HTTP server; status
  messages appear on screen; toasts report progress; "Rooting complete" when done.
- Gotchas we hit:
  - host firewall must allow the TV to connect back to your PC (`sudo ufw disable`
    during the exploit run, re-enable after);
  - close any running app (e.g. Plex) so the exploit app can launch — TV idle on home screen;
  - pass `--webos-version` if auto-selection picks a wrong app.
- Homebrew Channel is installed and auto-elevated; `devmode_enabled` becomes a
  permanent directory.

## 4. Lock it in (before rebooting!)
1. Homebrew Channel → Settings → enable SSH server; paste your SSH **public key**
   into the SSH key field (otherwise root password is the default `alpine`).
2. **Uninstall the LG Developer Mode app** from the home menu.
   ⚠️ Never reinstall it while rooted — it can wipe all apps.
3. Disable **Quick Start+** (All Settings → General → … → TV Management/Additional Settings).
4. Reboot (Homebrew Channel → "System reboot").
5. Verify: Homebrew shows *Root status: ok*; `ssh -p 22 root@<TV-IP>` with your key → uid 0.

Persistence mechanism: Homebrew `startup.sh` (root, early boot) +
`/var/luna/preferences/devmode_enabled` directory + elevated hbchannel service.
All reversible.

## 5. Kill telemetry (upload daemons, ACR, voice snooping)
Homebrew's startup hook already read-only-bind-mounts the upload spools.
Add a dot-free hook (busybox `run-parts` skips filenames with dots!):
```sh
# on the TV as root:
cp /tmp/telemetry-block.sh /var/lib/webosbrew/init.d/10-telemetry-block
chown root:root /var/lib/webosbrew/init.d/10-telemetry-block
chmod 755 /var/lib/webosbrew/init.d/10-telemetry-block
```
Hook script (`telemetry-block.sh` in this repo):
- stops + binary-blocks `remotelogger`, `uploadd`, `voiceinput`,
  `voiceconductor`, `faultmanager` (empty-file bind mounts → systemd can't respawn)
- empty-dir bind mounts over ACR/ad/data-collection apps:
  `acrcomponent`, `acroverlay`, `acrhdmi1-4`, `adoverlay`, `adoverlayex`,
  `adhdmi1-4`, `care365`, `dangbei-card`, `dangbei-overlay`, `com.webos.app.voice`
- deletes persistent ACR consent flags (`/var/luna/preferences/ACR_Launched`, `FirstPOPUPACR`)
- adds `snu-dev/snu-ssl/nsu.lge.com` to the boot-regenerated hosts blocklist

Verified after reboot: 0 telemetry processes, units inactive/failed, hooks re-applied.
Side effect: LG voice control / Alexa voice input dead (that's the point — the mic pipeline is disabled).

## 6. Ads gone + home-screen cleanup
Same hook (see `telemetry-block.sh` in this repo) bind-blocks — every boot, ~40 targets:
- transparent ad overlays: `adoverlay`, `adoverlayex`, `adhdmi1-4`, `dangbei-*`
- content/ad discovery: `premium`, `livedmost`, store-partition `cdp-30`
  (recommendation engine), sports (`sportsalert` service + settings app),
  weather helper, `membership`, `assetmanager`, LG remote management
  (`remoteservice/remotesetting`), update UI app, voice-assistant UI
  (Google/Alexa/voiceagent), demo+example junk apps
- exploit service `jsservicelauncher` (closes the jsserver attack surface)
Kept: home dashboard, liveTV/tuner, HDMI inputs, browsers, store, screensaver
(OLED burn-in protection!), notifications, your real store apps.
Ad payloads also can't download: all LG SNU/NSU hosts resolve to localhost.
Finish in the UI: long-press dashboard cards → remove leftovers; uninstall
unwanted store apps. Verified: survives reboot, TV boots fine, ads gone.

## 7. Updates disabled
Homebrew Channel setting "Block system updates" + our extra hosts entries
blackhole `snu*.lge.com`, `su*.lge.com`, `nsu.lge.com` → no OTA, no update nag.
Router-level DNS blocking of the same domains closes the early-boot gap.

## 8. Rollback
Reboot clears all bind mounts (transient). Delete the init.d hook; uninstall
Homebrew Channel; remove `/var/lib/webosbrew` and the `devmode_enabled`
directory → stock state. Nothing persistent is modified except the devmode marker.

## 9. Android TV outlook
Full flashing is blocked by LG secure boot (`secured` images + `sbkey`).
A userspace Android port onto the stock kernel looks plausible (extracted:
`mali_kbase.ko`, 18 MB Bifrost `libmali.so.0.1`, `/dev/fb0-fb3`, full ALSA,
evdev, MT7668 WiFi modules) — hard part is a Bifrost gralloc/EGL HAL + display
control RE. See `androidTvFeasibility.md` for the full study.

## Credits
- SlopBro / faultmanager / crashd / DejaVuln guides: throwaway96
- jsserver vuln first disclosed by raws0kil (jsbro-autoroot); dangbro overlay code: azoffshowy
- faultmanager vuln discovered by buglloc; webOS Homebrew community (webosbrew.org, OpenLGTV Discord)

*All device-specific identifiers (NDUID, serial, MACs, dev-mode PIN, IP) have been
removed from this guide.*
