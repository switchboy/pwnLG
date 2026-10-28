# pwnLG

**Take back your bought-and-paid-for LG webOS TV.**

A consumer toolkit that roots LG webOS TVs via a public exploit, then permanently
kills the spyware, microphone eavesdropping, content-recognition (ACR), ad overlays,
home-screen slop and OTA update nags — all with reversible, userspace-only tricks.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Status: WORKING](https://img.shields.io/badge/status-tested%20working-green)
![Tested on webOS 5.6.2](https://img.shields.io/badge/tested%20on-webOS%205.6.2-blue)
![Exploit range webOS 4–11](https://img.shields.io/badge/exploit%20covers-webOS%204%E2%80%9311-blueviolet)

---

> ### ⚠️ Read this first
> **NEVER write to system partitions** (kernel, rootfs, `tvservice`). A botched write
> bricks the TV permanently — not recoverable even by factory reset.
> See https://rootmy.tv/warning
> Everything in this repo uses bind-mounts and startup hooks only; fully reversible.
>
> **Never reboot while the Developer Mode app is installed, and never reinstall it
> while rooted** — it can wipe all your apps.
>
> This targets hardware **you bought and paid for**. Removing telemetry from your own
> device is a consumer action; in the EU it sits squarely in the spirit of GDPR
> ("consent must be freely given"). You do this at your own risk.

---

## What this toolkit does

| Goal | Status | How |
|---|---|---|
| Root the TV | ✅ | **SlopBro** exploit (jsserver vuln, webOS 4–11) → Homebrew Channel elevated to root |
| Root survives reboot | ✅ | Homebrew startup hook + permanent `devmode_enabled` marker + custom `init.d` hook |
| Spyware uploaders dead | ✅ | `uploadd`, `remotelogger`, `faultmanager`, `care365` stopped + binaries bind-blocked |
| Mic eavesdropping off | ✅ | `voiceinput`/`voiceconductor` + voice apps blocked (voice control/Alexa voice intentionally dead) |
| Content recognition (ACR) off | ✅ | ACR apps bind-blocked, consent flags deleted |
| Ad overlays gone | ✅ | `adoverlay/ex`, `adhdmi1-4`, dangbei ad framework blocked; ad/update hosts blackholed |
| Home-screen slop purged | ✅ | Recommendation engine (`cdp-30`), content hubs, sports/weather/membership services |
| OTA updates disabled | ✅ | All LG `snu/su/nsu` endpoints resolve to localhost, regenerated at every boot |
| Exploit door closed | ✅ | `jsservicelauncher` locked down after rooting (security bonus) |
| Windows support | ✅ | `pwnPatcher.bat` gives the same one-click experience |
| Android TV port research | 🔬 | Feasibility study + extracted hardware blobs (see below) |

## Tested hardware & versions

| Device | webOS | Firmware | OTAID | Exploit | Result |
|---|---|---|---|---|---|
| LG **OLED55CX6LA** (OLED CX 55", 2020, EU) | **5.6.2** (`jhericurl-jimna`) | **04.64.00** (build 21, release) | `HE_DTV_W20O_AFABABAA` | SlopBro | ✅ rooted, verified across **two full reboots**, SSH + hooks persist |

The block scripts are version-agnostic bind-mount hooks; they should work on any
rooted webOS ≥ 4.0 (app/service names vary slightly per generation — cross-check on
[cani.rootmy.tv](https://cani.rootmy.tv/) and adjust if needed). Older exploits
(crashd, faultmanager, WTA, dejavuln, RootMyTV) are patched on current firmware;
**SlopBro still covers webOS 4–11 including LG's patch workarounds** at time of testing.

## Quick start — the one-click patchers

From "Developer Mode app installed" to "rooted, spy-free, reboot-safe" in one run.
Keep these files in one folder: `pwnPatcher.sh`/`pwnPatcher.bat`, `pwnblock.sh`, `pwnpatch.sh`, `pwnreboot.sh`.

**Linux / macOS:**
```sh
cd pwnLG && bash pwnPatcher.sh
```
**Windows (10 1809+ / 11):** enable *OpenSSH Client* (Settings → Optional Features),
install Python 3 from python.org, then in Command Prompt:
```bat
cd pwnLG && pwnPatcher.bat
```

The patcher asks what to block — each with a short description, defaults in brackets
are the recommended choice:

| Question | Default | What it kills |
|---|---|---|
| Spyware upload daemons | **Y** | log/data uploads (`uploadd`, `remotelogger`, `faultmanager`, `care365`) |
| Voice eavesdropping | N | mic capture pipeline — pick `y` to disable listening (breaks LG voice/Alexa voice) |
| Content recognition (ACR) | **Y** | "what are you watching" tracking, incl. HDMI sources |
| Ad overlays | **Y** | ads on live TV / home screen / HDMI inputs + dangbei framework |
| Home-screen slop | **Y** | `cdp-30` recommendations, `premium`/`livedmost` hubs, sports alerts, weather widget, membership |
| LG remote support | **Y** | LG partner/diagnostic remote channels (`remoteservice/setting`) |
| Update screens | **Y** | OTA UI & update nags (servers blocked regardless) |
| Assistant UI | **Y** | Google Assistant / Alexa app UI (voice is dead if you blocked voice anyway) |
| Demo/example junk | **Y** | LG test apps (`store-demo`, `exampleapp.*`) |
| Screensaver | N (keep!) | OLED burn-in protection stays |
| Notification center | N (keep!) | Homebrew alerts stay visible |
| LG account | N (keep) | sign-in stays unless you never use LG account |

After rooting it generates a key, installs passwordless root SSH on port 22,
applies your choices, nags you (on-screen toast) to **uninstall the Developer Mode
app**, waits until you did, reboots the TV itself, and verifies everything.

Later root access: `ssh -p 22 -i pwn_ed25519 root@<TV-IP>` — no password.

---

## Full beginner guide (inline)

### Step 0 — Prep the TV (once)
1. Content Store → install the **Developer Mode** app.
2. Set **Dev Mode Status = ON** → reboot when asked.
3. Reopen the app → enable **Key Server** (fetches the SSH key once).
4. Note the **6-character passphrase** shown in the app.
5. Find the TV's IP in Settings → Network.
6. Recommended: turn **Quick Start+ OFF** (Settings → General → Additional Settings / TV Management).

### Step 1 — Prep your PC
- **Linux/macOS:** `ssh`, `scp`, `curl`, `ssh-keygen`, `python3`. Optional `sshpass` (auto-types the passphrase).
- **Windows:** OpenSSH Client (Optional Features), Python 3 from python.org (tick *Add to PATH*).
  If Windows Firewall blocks the exploit page: set network profile to **Private** or allow *Python* in firewall rules.
- **Linux with ufw:** the patcher offers to disable it during the run and re-enable it after.

### Step 2 — Run the patcher
Answer the prompts (TV IP, then the 6-char passphrase — case-sensitive).
On Windows you'll be asked for the passphrase ~6 times — normal; type the Dev Mode PIN each time.

### Step 3 — Watch the TV
The TV must be **idle** (close Plex/Netflix — otherwise the exploit app can't launch).
During the run: a **pairing prompt** appears → accept with the remote (first time only).
Then a status page loads from your PC and toasts report progress. If nothing appears, see troubleshooting.

### Step 4 — Uninstall the Developer Mode app (critical!)
Home menu → Developer Mode app → Remove. The patcher polls the TV every 5s and only
reboots once it's gone. **Never reboot with it installed.**

### Step 5 — Done
~60 s after the reboot the patcher verifies and prints SUCCESS. Long-press leftover
home-screen cards → delete; uninstall unwanted store apps yourself. Voice control is
dead if you chose the voice block — that's intentional.

### Rollback (un-patch)
```sh
ssh -p 22 -i pwn_ed25519 root@<TV-IP>
rm /var/lib/webosbrew/init.d/10-pwnpatch && reboot
```
Bind mounts vanish at reboot; uninstall Homebrew Channel for fully stock.

<details>
<summary><b>Troubleshooting (all gotchas we actually hit)</b></summary>

| Symptom | Fix |
|---|---|
| `Connection refused` on port 9991 | Enable **Key Server** in the Developer Mode app |
| `no matching host key type ... ssh-rsa` | TV sshd is legacy; patchers already use `-oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedKeyTypes=+ssh-rsa` |
| Exploit page never loads on TV | TV→PC blocked: disable firewall (`sudo ufw disable`), TV idle (close Plex!), same LAN subnet |
| Passphrase rejected | case-sensitive, read it fresh from the app |
| "Rooting complete" but no Homebrew after reboot | reboot again with Quick Start+ disabled |
| Exploit fails / firmware patched | check OTAID + firmware on [cani.rootmy.tv](https://cani.rootmy.tv/) |
| Connection drops during reboot | normal — patcher waits 60 s and reconnects |
| No root after reboot | Developer Mode app was still installed at reboot → remove it, re-run patcher (safe) |
| Voice control dead | you chose the voice block; intentional |
| Patches don't re-apply after reboot | hook filename must have **no dot** (`run-parts` skips dotted names!) — keep `10-pwnpatch` |

</details>

---

## How it works

1. **Root:** SlopBro serves an exploit page to the TV browser; a privileged Luna
   request installs a fake service whose `main.js` runs **as root** and installs +
   elevates Homebrew Channel.
2. **Persistence:** Homebrew's `/var/lib/webosbrew/startup.sh` (root, early boot) +
   `/var/luna/preferences/devmode_enabled` as a *directory* (dev-mode expiry disabled).
3. **Blocking:** our `init.d` hook (`10-pwnpatch`) re-applies bind-mounts every boot:
   empty tmpfs *files* over telemetry binaries (systemd can't respawn them), empty
   *dirs* over spy/ad apps (they can't launch), hosts entries blackholing LG
   update/ad endpoints, deletion of ACR consent flags. Homebrew additionally keeps
   upload spools (`/tmp/rdxd`, `/var/spool/uploadd/*`) read-only.
4. **Nothing persistent** is written to system partitions; rebooting without the
   hook restores stock behavior.

Gotchas encoded in the scripts (learned the hard way): dot-free `run-parts` name,
legacy `ssh-rsa` host-key algorithms, firewall must allow TV→PC during exploit,
TV must be idle for app launch, Dev Mode app must be gone before first reboot.

## Repo layout

| File | Purpose |
|---|---|
| `pwnPatcher.sh` / `pwnPatcher.bat` | one-click interactive patchers (Linux/macOS / Windows) |
| `pwnblock.sh` | on-TV boot hook — flag-gated bind-mount blocking |
| `pwnpatch.sh` | root-side installer: key, hook, Homebrew flags, SSH server |
| `pwnreboot.sh` | reboot helper (run only after Dev Mode app removed) |
| `pwnPatchGuide.md` | full beginner guide (inlined above too) |
| `wayToPwnLG.md` | complete manual — manual steps, compat checks, Android outlook |
| `exploit.md` | our exploit analysis log (patch-status math, execution) |
| `workingPersistence.md` / `persistentRootAttempts.md` | persistence verification records |
| `removeTelemetryAttempt.md` / `successfulTelemetryRemoval.md` | telemetry removal log/report |
| `removeAdsAttempt.md` / `successfulAdRemoval.md` | ad/home-slop removal log/report |
| `successfulUpdateDisabled.md` | update-blocking procedure |
| `androidTvFeasibility.md` | Android TV port feasibility study |

Deliberately **not** committed: device backups, hardware blobs, credentials,
`context.md` (contains device-specific identifiers).

## Android TV outlook (summary)

Flashing Android TV onto this TV is **not consumer-feasible**: LG firmware is
`secured` images + verified boot (`sbkey`, `prodkey`) — replacing kernel/rootfs
requires LG hardware debug tokens (AccessUSB). *However* an Android-userspace port
onto the stock kernel looks plausible: extracted blobs include `mali_kbase.ko`,
an 18 MB Bifrost `libmali.so.0.1` DDK, framebuffer devices `/dev/fb0-fb3`, full
ALSA and evdev, MT7668 WiFi modules. Hard part: a Bifrost gralloc/EGL HAL + display
control RE. Full study: [`androidTvFeasibility.md`](androidTvFeasibility.md).

## Credits & license

- **SlopBro** exploit (throwaway96) — https://github.com/throwaway96/slopbro
  (AGPL-3.0; downloaded at runtime, not embedded here)
- jsserver vuln first disclosed by **raws0kil** (jsbro-autoroot); `dangbei-overlay`
  code from **dangbro** (azoffshowy); faultmanager vuln discovered by **buglloc**
- Older exploit guides: **crashd/faultmanager/dejavuln** guides (throwaway96),
  **RootMyTV** (Recurity Labs), CVE-2023-6318 / CVE-2024-1886 (Bitdefender, brzozowski.io)
- Community: [webosbrew.org](https://www.webosbrew.org/) · [cani.rootmy.tv](https://cani.rootmy.tv/) · OpenLGTV Discord

Everything in *this* repository is **MIT licensed** (our scripts & docs).
This is research on consumer-owned hardware; use responsibly.
