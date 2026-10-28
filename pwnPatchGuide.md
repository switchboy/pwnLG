# pwnPatcher Guide — one-click rooting & spyware removal for your LG webOS TV

This walks a beginner from "I just installed the Developer Mode app" to a
rooted TV where spyware, voice eavesdropping, content tracking, ads and
update-nags are permanently blocked — and it survives reboots.

Two scripts do the same job:
- **Linux/macOS:** `pwnPatcher.sh` (run in a terminal)
- **Windows:** `pwnPatcher.bat` (run in Command Prompt / double-click)

Keep these files in the SAME folder:
`pwnPatcher.sh` (or `.bat`) + `pwnblock.sh` + `pwnpatch.sh` + `pwnreboot.sh`

> ⚠️ **Golden rules**
> 1. Never write to system partitions (kernel/rootfs/tvservice) — that bricks the TV.
>    This patcher never does; everything is reversible userspace stuff.
> 2. **Never reboot while the Developer Mode app is installed**, and never reinstall
>    it after rooting — it can wipe all your apps.
> 3. Your TV must be idle (close Plex/Netflix etc.) during the exploit.

## Step 0 — Prep the TV (once)
1. On the TV: Content Store → search **Developer Mode** → install the app.
2. Open it → set **Dev Mode Status = ON** → reboot the TV when asked.
3. Open it again → enable **Key Server** (needed only to fetch the SSH key once).
4. Note the **6-character passphrase** displayed in the app.
5. Find the TV's IP: Settings → Network (wired or Wi-Fi). Use that IP.
6. Recommended: Settings → General → (Additional Settings / TV Management) →
   turn **Quick Start+ OFF** so power-off really reboots.

## Step 1 — Prep your PC
**Linux/macOS terminal:** you need `ssh`, `scp`, `curl`, `ssh-keygen`, `python3`
(all usually preinstalled; Python 3 from your package manager if not).
Optional: `sshpass` (Linux) makes the script auto-type the passphrase — then you
never type anything. Without it you'll be asked for the passphrase a few times.
On Linux with ufw firewall the script offers to disable it during the run and
re-enable it after.

**Windows:** Windows 10 1809+ or 11. Install:
- OpenSSH Client: Settings → Optional Features → add "OpenSSH Client"
  (gives you ssh, scp, ssh-keygen, curl)
- Python 3: from python.org — tick **"Add python.exe to PATH"** during install
- If Windows Firewall blocks the exploit page: set your network to **Private**
  (Settings → Network) or allow "Python" in firewall's "Allow an app" list.

## Step 2 — Run the patcher
Linux/macOS:
```sh
cd pwnLG          # the folder containing the scripts
bash pwnPatcher.sh
```
Windows: open **Command Prompt** (cmd), `cd` to the folder, run:
```
pwnPatcher.bat
```
(or just double-click it)

The script asks:
| Prompt | What to enter |
|---|---|
| TV IP address | the IP from Step 0 |
| 6-char passphrase | exactly as shown in the Dev Mode app (case matters!) |
| Block spyware upload daemons? | **Enter = Y** — logs/data uploaded to LG get killed |
| Block voice eavesdropping? | **Enter = N** — type `y` to kill mic capture (LG voice control & Alexa voice then stop working) |
| Block content recognition (ACR)? | **Enter = Y** — stops "what are you watching" tracking |
| Block ad overlays? | **Enter = Y** — kills ads on live TV / HDMI / home screen |
| Block home-screen slop? | **Enter = Y** — recommendation engine, sports alerts, weather widget, membership, content hubs |
| Block LG remote support? | **Enter = Y** — LG partner/diagnostic remote channels |
| Block update screens? | **Enter = Y** — no more update UI/nags (servers blocked anyway) |
| Block assistant UI? | **Enter = Y** — Google Assistant / Alexa app UI gone |
| Block demo/example apps? | **Enter = Y** — LG test-app junk gone |
| Block screensaver? | **Enter = N** (keep!) — protects your OLED panel from burn-in |
| Block notification center? | **Enter = N** (keep!) — Homebrew alerts stay visible |
| Block LG account? | **Enter = N** (keep) — unless you never use LG account |

Windows: whenever ssh.exe prompts for a **passphrase**, type your 6-char Dev
Mode PIN again. Expect ~6 prompts; that's normal.

## Step 3 — Watch the TV (exploit phase)
The script downloads the SlopBro exploit and runs it. On the TV:
1. A **pairing prompt** appears → press OK/Accept on the remote (first time only).
2. A status page appears on screen, then **toasts**: "Installing..." → "Rooting complete".
3. A **pwnLG toast** will tell you to uninstall the Developer Mode app.

If nothing appears on the TV: see Troubleshooting below.

## Step 4 — Uninstall the Developer Mode app (important!)
On the TV: home/menu → highlight **Developer Mode** app → Remove/Uninstall.
The script waits for this automatically (it checks the TV every 5 seconds) and
then reboots the TV itself.

## Step 5 — Done
After the reboot (~60 s) the script verifies everything and prints SUCCESS.
From now on:
- Root terminal anytime: `ssh -p 22 -i pwn_ed25519 root@<TV-IP>` (Linux/Windows, no password)
- Homebrew Channel app on the TV shows **Root status: ok**
- Updates: LG update servers are blackholed (localhost) — no OTA, no nags
- Telemetry/ACR/voice uploaders: dead, re-blocked at every boot
- Home screen: long-press leftover cards → delete; uninstall unwanted store apps yourself

## Rollback (un-patch)
```sh
ssh -p 22 -i pwn_ed25519 root@<TV-IP>
rm /var/lib/webosbrew/init.d/10-pwnpatch
reboot        # bind mounts vanish; TV behaves stock again
```
(Then uninstall Homebrew Channel if you want fully stock.)

## Troubleshooting (all real-world gotchas we hit)
| Symptom | Fix |
|---|---|
| `Connection refused` fetching key on 9991 | Enable **Key Server** in the Dev Mode app |
| SSH: `no matching host key type ... ssh-rsa` | scripts already use legacy flags; double-check you edited nothing |
| Pairing prompt never appears / exploit page never loads | TV→PC blocked: disable firewall (`sudo ufw disable` on Linux; Private network / allow Python on Windows), TV idle (close Plex), same LAN subnet |
| "Rooting complete" but Homebrew missing after reboot | reboot again with Quick Start+ disabled |
| Passphrase rejected | case-sensitive, no spaces; re-read it from the app |
| Script says exploit failed / patched firmware | check your OTAID+firmware on https://cani.rootmy.tv/ |
| Connection drops mid-reboot | normal — script waits 60 s and reconnects |
| TV boots but patcher says no root | Dev Mode app was still installed at reboot — remove it, re-run patcher (re-running is safe) |
| Voice control stopped working | you chose the voice block — that's intentional (mic pipeline disabled) |

## What exactly gets blocked (details)
See `pwnblock.sh` header comments — every flag maps to one menu question.
Always-on extras: LG update/ad domains (`snu*.lge.com`, `su*.lge.com`,
`nsu.lge.com`) resolve to localhost; the exploit's own service
(`jsservicelauncher`) is locked down for security; Homebrew's startup hook
keeps upload spools read-only.
Deliberately kept (defaults): home dashboard, Live TV + tuner, HDMI/AV inputs,
browser apps, Content Store, screensaver (OLED!), notifications, LG account,
your real streaming apps.

*Related docs in this folder: `wayToPwnLG.md` (the full manual), `exploit.md`
(findings), `pwnPatchGuide.md` (this file).*
