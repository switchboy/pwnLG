# Android TV on LG OLED55CX6LA (webOS 5, O20 SoC) — feasibility study

## Hardware inventory (extracted via root, see backup/blobs/)
| Component | Interface | Android compatibility |
|---|---|---|
| SoC | LG "O20B0" ARM aarch64, 3 GB RAM, 8 GB eMMC (mmcblk0, A/B slot rootfs p27/p38) | standard |
| Kernel | LG 4.4.84 custom (jcl4tvmr), cmdline: chip=O20B0, HMA 856M+360M reserved, cma, criu snapshot resume=p51 | limits Android to ≤10 (4.4 kernel) |
| GPU | Arm **Mali Bifrost** via `mali_kbase.ko` + `/dev/mali0` char device; userspace blob `libmali.so.0.1` (18 MB DDK, Bifrost codepaths confirmed by strings) | usable, needs gralloc/EGL HAL wrapper |
| Display | `/dev/fb0..fb3` + `dc_fbdev` (framebuffer interface!), proprietary panel/HDMI control in `videooutputd` + libdrm* glue libs | framebuffer HAL plausible; input-switch logic needs RE |
| Audio | full ALSA (`/dev/snd`: pcm playback + capture) | standard ALSA audio HAL |
| Input | standard evdev (`/dev/input/event*`) | standard |
| WiFi/BT | MediaTek MT7668/7663 USB (wlan_mt7668.ko, btmtk_usb.ko pulled) | upstream-ish Linux drivers → wpa-supplicant works |
| DVB tuner | a8303/rda5815/si2178 frontends (Linux DVB modules present) | Tuner HAL via DVB API possible |
| Storage/USB | standard eMMC/USB | standard |

## The blocker: secure boot
Firmware image is `lib32-starfish-dvb-secured`, cmdline carries `sbkey=0x7d0e0000`,
`encryption_key_type=prodkey`, boot partitions p1-p14 (verified chain). Replacing
kernel/rootfs with Android = **blocked without LG hardware debug access**
(AccessUSB token / EEPROM debug only on webOS ≤3.x platforms). So *flashing*
Android TV onto this device is not consumer-feasible.

## Feasible path: Android userspace ON the existing webOS kernel
Secure boot only validates kernel+rootfs — userspace is unrestricted once rooted.
Plan:
1. Build Android 10 AOSP (aarch64, kernel 4.4 OK) system image as a chroot/rootfs
   on the writable data partition (p55) or SD/USB ext4.
2. Launch via the root startup hook (`/var/lib/webosbrew/init.d/`) *after* webOS
   early init: stop webOS target (`systemctl stop default-webos.target`) to free
   the GPU/display, then start Android init inside the rootfs.
   Watch out: snapshot boot (criu, `resume=/dev/mmcblk0p51`) restores webOS state —
   disable Quick Start+ so Android starts from clean boot.
3. HALs to write:
   - **gralloc**: wrap `libmali.so.0.1` buffer allocation (`mali_egl_image_get_buffer_ext`)
     + kbase memory mgmt (HMA regions in cmdline). Critical path, hardest part.
   - **EGL/GLES**: LG's libEGL shim + libmali directly (GBM absent → char-device DDK path).
   - **composer/HAL display**: use `/dev/fb0` (standard fb) — SurfaceFlinger fb backend;
     panel modes owned by `videooutputd`; either keep videooutputd idle or RE its kdrv ioctls.
   - **audio**: stock AOSP ALSA HAL (config: pcmC0D0p etc).
   - **input**: stock evdev HAL.
   - WiFi: mt7668 driver + wpa_supplicant (pull .ko files; already done).
4. Extract remaining blobs needed: full rootfs squashfs (p27) for reference,
   `/var/luna/preferences` untouched; keep extracted blob set in backup/blobs/.

## Verdict
- **Flashing Android TV**: NOT feasible (secure boot, no consumer debug path).
- **Android-on-webOS (coexistence/port)**: plausible-medium effort. Standard-ish
  fb/audio/input/wifi interfaces are a big blessing; the hard part is the
  Bifrost gralloc/EGL HAL against LG's renamed 18 MB DDK blob and the
  display-control stack (videooutputd + custom "lg1k" kernel driver).
- Realistic interim alternative: plain Linux chroot (Debian) via startup hook for
  non-GPU workloads (Kodi software-rendering too slow on 3 GB RAM; better:
  lightweight desktop/apps using libmali directly).

## Next research steps
1. Identify exact DDK version of libmali.so.0.1 (symbol diff vs Arm releases) →
   find matching gralloc HAL source for Bifrost.
2. strace videooutputd on live TV to map its kdrv ioctls (strace exists in
   /opt/devmode or as root /usr/bin? verify).
3. Test launching a chroot with a minimal EGL test app using libmali + /dev/mali0
   while webOS UI is stopped — proves GPU access from foreign userspace.
4. Check whether `debugMode=5` in cmdline + serial console (ttyAMA0) gives a
   kernel debug shell (hardware UART) — would ease RE and allow custom-kernel
   experiments if boot verification is lenient for debug builds.
