@echo off
setlocal EnableDelayedExpansion
title pwnPatcher v1.0 - take back your LG webOS TV
chcp 65001 >nul 2>&1

echo ============================================================
echo   pwnPatcher v1.0 - take back your LG webOS TV (Windows)
echo ============================================================
echo Safety: never write to system partitions (kernel/rootfs/tvservice).
echo This patcher only uses userspace tricks (bind mounts + startup hooks). Reversible.
echo.
echo You need: TV IP + the 6-char passphrase shown in the Developer Mode app.
echo When ssh.exe asks for the "passphrase", TYPE THAT PASSPHRASE. Expect ~6 prompts.
echo.

where ssh.exe >nul 2>&1 || goto miss_ssh
where scp.exe >nul 2>&1 || goto miss_ssh
where ssh-keygen.exe >nul 2>&1 || goto miss_ssh
where curl.exe >nul 2>&1 || goto miss_curl
(py -3 --version >nul 2>&1 || python --version >nul 2>&1) || goto miss_python

set /p TV_IP=TV IP address [192.168.1.119]: 
if "!TV_IP!"=="" set TV_IP=192.168.1.119
echo Make sure: Developer Mode app installed, Dev Mode Status = ON, Key Server enabled.
set /p PIN=6-char passphrase from the Developer Mode app (case-sensitive): 

set SSHOPTS=-p 9922 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=8
set ROOTSSH=ssh -p 22 -i pwn_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=8 root@%TV_IP%

echo.
echo Fetching SSH key from TV (port 9991)...
curl -f -s -m 10 http://%TV_IP%:9991/webos_rsa -o webos_rsa || goto fail_key

echo Reading TV info (ssh will ask passphrase - type the 6-char PIN)...
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "cat /var/run/nyx/device_info.json" > device_info.json 2>nul
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "cat /var/run/nyx/os_info.json" > os_info.json 2>nul
powershell -NoProfile -Command "$d=Get-Content device_info.json|ConvertFrom-Json; $o=Get-Content os_info.json|ConvertFrom-Json; Write-Host ('Model='+$d.product_id+' OTAID='+$d.hardware_id+' firmware='+$o.webos_manufacturing_version+' webOS='+$o.core_os_release)"
powershell -NoProfile -Command "$o=Get-Content os_info.json|ConvertFrom-Json; Write-Output (($o.core_os_release -split '\.')[0])" > ver.txt
set /p MAJOR=<ver.txt
echo Exploit check if it fails: https://cani.rootmy.tv/

echo.
echo Pick what to BLOCK (press Enter to accept the default in brackets):
set /p SPY=Block SPYWARE upload daemons (uploadd/remotelogger/faultmanager/care365) [Y/n]: 
if "!SPY!"=="" set SPY=Y
set /p VOICE=Block VOICE eavesdropping - breaks LG voice/Alexa voice! [N/y]: 
if "!VOICE!"=="" set VOICE=N
set /p ACR=Block CONTENT RECOGNITION (ACR) apps [Y/n]: 
if "!ACR!"=="" set ACR=Y
set /p ADS=Block AD OVERLAYS (live TV, home, HDMI, dangbei) [Y/n]: 
if "!ADS!"=="" set ADS=Y
set /p SLOP=Block HOME SLOP (cdp-30 recommendations, premium/livedmost, sports, weather, membership) [Y/n]: 
if "!SLOP!"=="" set SLOP=Y
set /p REMOTESVC=Block LG REMOTE SUPPORT channels (remoteservice/remotesetting) [Y/n]: 
if "!REMOTESVC!"=="" set REMOTESVC=Y
set /p UPDUI=Block LG UPDATE SCREENS [Y/n]: 
if "!UPDUI!"=="" set UPDUI=Y
set /p ASSIST=Block VOICE ASSISTANT UI (Google/Alexa apps) [Y/n]: 
if "!ASSIST!"=="" set ASSIST=Y
set /p JUNK=Block LG DEMO/EXAMPLE junk apps [Y/n]: 
if "!JUNK!"=="" set JUNK=Y
set /p SCREENSAVER=Block SCREEN SAVER (OLED burn-in!) [N/y]: 
if "!SCREENSAVER!"=="" set SCREENSAVER=N
set /p NOTIFY=Block NOTIFICATION CENTER [N/y]: 
if "!NOTIFY!"=="" set NOTIFY=N
set /p ACCOUNT=Block LG ACCOUNT (homeconnect) [N/y]: 
if "!ACCOUNT!"=="" set ACCOUNT=N

set FLAGS=
if "!SPY:~0,1!"=="Y" set FLAGS=!FLAGS! --spy
if "!SPY:~0,1!"=="y" set FLAGS=!FLAGS! --spy
if "!VOICE:~0,1!"=="Y" set FLAGS=!FLAGS! --voice
if "!VOICE:~0,1!"=="y" set FLAGS=!FLAGS! --voice
if "!ACR:~0,1!"=="Y" set FLAGS=!FLAGS! --acr
if "!ACR:~0,1!"=="y" set FLAGS=!FLAGS! --acr
if "!ADS:~0,1!"=="Y" set FLAGS=!FLAGS! --ads
if "!ADS:~0,1!"=="y" set FLAGS=!FLAGS! --ads
if "!SLOP:~0,1!"=="Y" set FLAGS=!FLAGS! --slop
if "!SLOP:~0,1!"=="y" set FLAGS=!FLAGS! --slop
if "!REMOTESVC:~0,1!"=="Y" set FLAGS=!FLAGS! --remotesvc
if "!REMOTESVC:~0,1!"=="y" set FLAGS=!FLAGS! --remotesvc
if "!UPDUI:~0,1!"=="Y" set FLAGS=!FLAGS! --updui
if "!UPDUI:~0,1!"=="y" set FLAGS=!FLAGS! --updui
if "!ASSIST:~0,1!"=="Y" set FLAGS=!FLAGS! --assist
if "!ASSIST:~0,1!"=="y" set FLAGS=!FLAGS! --assist
if "!JUNK:~0,1!"=="Y" set FLAGS=!FLAGS! --junk
if "!JUNK:~0,1!"=="y" set FLAGS=!FLAGS! --junk
if "!SCREENSAVER:~0,1!"=="Y" set FLAGS=!FLAGS! --screensaver
if "!SCREENSAVER:~0,1!"=="y" set FLAGS=!FLAGS! --screensaver
if "!NOTIFY:~0,1!"=="Y" set FLAGS=!FLAGS! --notify
if "!NOTIFY:~0,1!"=="y" set FLAGS=!FLAGS! --notify
if "!ACCOUNT:~0,1!"=="Y" set FLAGS=!FLAGS! --account
if "!ACCOUNT:~0,1!"=="y" set FLAGS=!FLAGS! --account
echo Selected:%FLAGS%

echo.
echo Windows firewall: if the TV's exploit page never loads, allow Python
echo (Settings - Update^&Security - Windows Firewall - Allow an app) or set your
echo network profile to Private, then retry.
echo.

if exist slopbro\slopbro.py goto have_slopbro
echo Downloading SlopBro exploit...
curl -f -L -s -m 30 -o slopbro.zip https://github.com/throwaway96/slopbro/archive/refs/heads/main.zip || goto fail_dl
(py -3 -c "import zipfile,shutil,os; zipfile.ZipFile('slopbro.zip').extractall('.'); shutil.rmtree('slopbro', ignore_errors=True); os.rename('slopbro-main','slopbro')") || python -c "import zipfile,shutil,os; zipfile.ZipFile('slopbro.zip').extractall('.'); shutil.rmtree('slopbro', ignore_errors=True); os.rename('slopbro-main','slopbro')" || goto fail_dl
:have_slopbro

echo.
echo TV-side: close ALL apps (e.g. Plex) so the TV is idle on the home screen.
echo During the exploit a PAIRING prompt appears on the TV - accept it with the remote.
echo Then watch the TV screen: status page + toasts report progress.
echo Running exploit (webOS %MAJOR%)...
(py -3 slopbro\slopbro.py --debug --webos-version %MAJOR% %TV_IP%) || python slopbro\slopbro.py --debug --webos-version %MAJOR% %TV_IP% || goto fail_exploit
echo Payload delivered - Homebrew Channel installs (watch TV toasts).

if exist pwn_ed25519 goto have_key
ssh-keygen -q -t ed25519 -N "" -f pwn_ed25519
:have_key

echo Pushing patch scripts (type passphrase when asked)...
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "cat > /tmp/pwnblock.sh" < pwnblock.sh || goto fail_push
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "cat > /tmp/pwnpatch.sh" < pwnpatch.sh || goto fail_push
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "cat > /tmp/pwnreboot.sh" < pwnreboot.sh || goto fail_push
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "cat > /tmp/pwn_pubkey.txt" < pwn_ed25519.pub || goto fail_push

echo Applying patches (type passphrase one last time)...
ssh %SSHOPTS% -i webos_rsa prisoner@%TV_IP% "sh /tmp/pwnpatch.sh %FLAGS%" | findstr PWN_DONE >nul || goto fail_patch
echo Root SSH server is now running on port 22 (your new key works - no passwords).

echo.
echo GO TO THE TV NOW: home menu - Developer Mode app - Remove app.
echo The TV must reboot WITHOUT the Dev Mode app installed. Waiting...
set CNT=0
:poll
set /a CNT+=1
%ROOTSSH% "ls -d /media/cryptofs/apps/usr/palm/applications/com.palmdts.devmode >nul 2>&1 && echo STILL || echo GONE" | findstr GONE >nul && goto reboot
if !CNT! geq 60 goto fail_wait
timeout /t 5 >nul
goto poll

:reboot
echo Rebooting TV...
%ROOTSSH% "sh /tmp/pwnreboot.sh" >nul 2>&1
echo Connection drops during reboot (normal). Waiting ~60 seconds...
timeout /t 60 >nul

%ROOTSSH% "id" | findstr uid=0 >nul || goto fail_root
echo.
echo ============================================================
echo   SUCCESS - TV rooted, spyware/ads/update-nags gone, reboot-safe.
echo ============================================================
echo   Root shell later:  ssh -p 22 -i pwn_ed25519 root@%TV_IP%
echo   Homebrew Channel app shows Root status ok.
echo   Rollback: ssh in, delete /var/lib/webosbrew/init.d/10-pwnpatch, reboot.
echo   NEVER reinstall the Developer Mode app while rooted!
echo   Home screen leftovers: long-press cards - delete; uninstall store apps.
echo   Disable Quick Start+ in Settings if you want off/on = real reboot.
echo ============================================================
goto end

:miss_ssh
echo ERROR: ssh.exe/scp.exe missing. Enable OpenSSH Client: Settings -> Optional Features.
goto end_fail
:miss_curl
echo ERROR: curl.exe missing (Windows 10 1809+). Update Windows or use pwnPatchGuide.md options.
goto end_fail
:miss_python
echo ERROR: Python 3 missing. Install from python.org and tick "Add python.exe to PATH".
goto end_fail
:fail_key
echo ERROR: cannot fetch key from port 9991. Enable "Key Server" in the Developer Mode app, retry.
goto end_fail
:fail_dl
echo ERROR: SlopBro download failed (internet / GitHub?).
goto end_fail
:fail_exploit
echo ERROR: exploit failed. Accept pairing on TV? TV idle (close Plex)? Firewall allowing Python?
echo Check firmware vulnerability on https://cani.rootmy.tv/
goto end_fail
:fail_push
echo ERROR: pushing scripts failed (wrong passphrase? Dev Mode ON?).
goto end_fail
:fail_patch
echo ERROR: patch step failed. Re-run the patcher.
goto end_fail
:fail_wait
echo ERROR: timeout waiting for Developer Mode app removal. Uninstall it on the TV, re-run patcher.
goto end_fail
:fail_root
echo ERROR: no root SSH after reboot. Re-run pwnPatcher or consult the guide.
goto end_fail
:end_fail
echo See pwnPatchGuide.md for troubleshooting.
exit /b 1
:end
pause
exit /b 0
