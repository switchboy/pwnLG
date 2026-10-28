# Successful update disabling — procedure

1. Homebrew Channel app → Settings → toggle "Block system updates".
   Its startup hook bind-mounts a regenerated `/etc/hosts` at boot containing:
   `127.0.0.1/::1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com`
2. Our init.d hook adds: `snu-dev.lge.com snu-ssl.lge.com`.
   **Correction (post-test):** `nsu.lge.com` was also blocked initially and had to be
   removed — it is the LG **Content Store API**, so blocking it broke store search and
   app installs. Firmware updates only use `snu/su/snu-dev/snu-ssl`.
   Result: all LG SNU/SU update endpoints resolve to localhost → OTA checks fail
   and update notifications stop. Verified post-reboot in `/etc/hosts`.
3. Belt & braces (optional): block the same domains on your router/DNS too —
   startup scripts run late in boot, so router-level blocking closes the gap.

Note: `update`/`uploadd` binaries remain but `uploadd` is stopped+binary-blocked
by the telemetry hook. Updates can also be re-enabled simply by removing hosts
entries / toggling Homebrew setting.
