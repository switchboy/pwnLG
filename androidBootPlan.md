# Android TV bring-up plan for the rooted LG OLED55CX (O20B0)

Goal: run AOSP Android TV natively on this TV's hardware, as bare metal as we can
get it. No emulation, no VM, no translation layer. Android owns the SoC, GPU,
display, audio and inputs when it runs.

Status: planning complete, execution not started. Phase 0 needs the TV powered on.

Related: `androidTvFeasibility.md` (hardware survey), `wayToPwnLG.md` (rooting and
persistence), `pwnblock.sh` / `telemetry-block.sh` (boot hooks).

---

## Locked decisions

1. AOSP 13 LTS arm64, trimmed to a TV build.
2. HDMI inputs first. DTV tuner deferred to its own phase (Phase 7).
3. Boot stays opt-in from the command line until Android is stable. No boot hook
   arms Android automatically.
4. No hardware serial assumed. Recovery is built from software layers plus LG's own
   crash dumps. Checking internal UART pins is optional, not a gate.
5. An 8 GB USB memory stick is a hard requirement for Android storage, because the TV's
   flash has only 481 MB free. The stick holds images, logs, the webOS kernel copy and
   `/data`. Pulling it removes Android entirely.

---

## Constraints that decide the shape of the project

| Fact | Consequence |
|---|---|
| LG images are `secured`, verified boot at SBL/ABL with `sbkey`/`prodkey` | Flashing Android kernel/rootfs into the flash partitions is not possible without LG debug tokens. Writing system partitions also bricks the panel. |
| Secure boot verification happens before webOS handoff | `kexec` from a rooted webOS kernel bypasses signature checks. This is the only viable bare-metal boot path. |
| Root is persistent via Homebrew `init.d` hook | The Android trigger can live in webOS userspace, and webOS always comes back on reboot. |
| SoC is `chip=O20B0`, vendor ARM64 | Device tree, power domains, clock controllers and GPU bring-up are all LG-specific. Nothing generic applies. |
| `mali_kbase.ko` allocates through ION and exports dma-buf | Gralloc becomes an ION heap-mask alignment task, not a memory-stack RE project. |
| `console=ttyAMA0,115200n81` in the stock cmdline | A UART is configured in the kernel. Internal pins may exist on the mainboard. Nice to have, not required. |
| Stock cmdline has `mmcoops=dump` and `wdtlog=dump@1M` | LG already writes kernel crash and watchdog dumps to storage. Free recovery layer, readable after a hard reboot into webOS. These are LG drivers, so they must be carried into our Android kernel build. |
| Stock cmdline has `snapshot resume=/dev/mmcblk0p51` | Android cmdline must drop `resume=` and snapshot settings, or Android may try to resume into a webOS suspend image. |
| Phase 0 confirmed: `CONFIG_DRM is not set`, `/dev/fb0`..`/dev/fb3` and `dc_fbdev` exist | The display target is framebuffer, not DRM. Android hwcomposer must be fb-based. |
| Phase 0 confirmed: `CONFIG_ION=y` plus `CONFIG_ION_LG1K=y`, no dma-buf heaps in stock config | Gralloc targets LG's ION driver through Android's legacy ION path, not dma-buf heaps. |
| Phase 0 confirmed: `CONFIG_KEXEC=y` but no `CONFIG_KEXEC_FILE` | `kexec_load` only, so the DTB must be passed explicitly with `--dtb=`. |
| Phase 0 confirmed: `CONFIG_MODULE_SIG is not set` | Unsigned modules load, which keeps an out-of-tree fallback open. Primary plan is built-in binder and ashmem in our kernel. |
| Phase 0 confirmed: `/var` has only 481 MB free | A full AOSP rootfs cannot live on the TV's flash. **Revision: an 8 GB USB memory stick is now a hard requirement** for Android storage. See the storage design below. |
| DTB declares `kdrv_buffer1@1` (0x33800000, 1.24 GB) and `kdrv_buffer2@2` (0xa9800000, 360 MB) as `no-map` carveouts | These are LG's CMA and HMA regions. Our Android kernel reuses them instead of inventing new reserved regions, and keeps cmdline `hma=` plus `lg1k.` parameters because LG's kbase probes as a platform device with no DT GPU node. |
| DTB declares 4x Cortex-A55, `nproc` reports 3 online, 3 GiB physical RAM | arm64 with NEON, AES, SHA1/SHA2, atomics. Memory budget for Android is about 2.4 GB once webOS is gone. |
| DTB declares `lge,lg115x-dwmac` plus `ethernet-phy-id0044.1400` | Wired Ethernet bring-up is standard `snps,dwmac` work. `eth0` currently has no carrier, so the TV needs a cable for the debug path. |

---

## Boot strategy: opt-in `kexec`

Flow:

1. webOS boots normally, telemetry blocks apply, root SSH works.
2. Operator runs `pwnandroid.sh` over root SSH. It stages the Android kernel image,
   initramfs, rootfs and DTB, runs pre-flight checks, then `kexec -l` plus `kexec -e`.
3. Android runs on real hardware. webOS is idle in RAM, not running, not mounted read-write
   by Android.
4. Return to webOS: `pwnback-to-webos` from Android (Android kexecs back into the staged
   webOS kernel), or a plain power cycle.

Why this is safe: `kexec` does not persist. Nothing is written to boot or recovery
partitions. A hard Android hang is recovered by power cycling into stock webOS.
Quick Start+ stays off so power-off is a real reboot. Developer Mode app stays
uninstalled forever.

`kexec_file_load` is unavailable on this kernel (Phase 0: no `CONFIG_KEXEC_FILE`), so
legacy `kexec_load` is the path and the DTB must be passed explicitly with `--dtb=` using
the dump from `backup/stock_tv.dtb`.

Auto-boot hook (`/var/lib/webosbrew/init.d/20-android-boot`, dot-free, `run-parts` skips
names containing a dot) exists only after gate G3 passes, and remains opt-in by flag file.
It only arms when the stick is present and the manifest verifies, so a missing stick always
falls back to plain webOS boot.

---

## Recovery layers, in order of reliability

1. LG kernel crash dumps: `wdtlog=dump@1M`, `mmcoops=dump`. Survive a kernel panic with
   no userspace alive. Readable from webOS after reboot. Partition offsets confirmed in
   Phase 0.
2. Shared log directory on the USB stick: Android writes boot logs to
   `pwnandroid/logs/` on the stick's webOS-readable FAT/exFAT partition, so webOS can read
   them after rebooting back with the stick still plugged. Files opened with `O_SYNC` plus a
   periodic `sync` from the logging daemon, so a freeze does not leave truncated or zero-byte
   logs. FAT has no journal, so a hard hang can still lose the last few lines. The LG dump
   drivers cover the gap where userspace never ran.
3. Early dropbear in Android init, started in the core class before hwcomposer and
   surfaceflinger, so a crashing graphics HAL cannot block shell access. Key is the
   existing `pwn_ed25519` key, no default password on the LAN.
4. adb over TCP by default during bring-up: `persist.adb.tcp.port 5555`, `ro.debuggable=1`,
   SELinux permissive. Useful for logcat, dumpSurfaceFlinger and HAL debugging.
5. Static IP fallback configured in init before netd, so a DHCP failure during bring-up
   does not lock us out. Wired Ethernet is the debug path (AOSP TV builds have
   `EthernetTracker`). MT7668 WiFi comes later for normal use.
6. `CONFIG_PSTORE` plus `CONFIG_PSTORE_RAM` in the Android kernel, so panics leave a
   readable trace in the shared directory on the next boot. Optional but worth having.
7. Optional: internal UART pins on the O20B0 mainboard at 115200. If found, it beats all
   software layers. Nice-to-have visual check when the chassis is open.

---

## Phase 0: live survey (TV powered on, read-only)

Status: DONE on 2026-11-02. Findings in `phase0-findings.md`, raw capture in
`backup/phase0-survey.raw`, DTB in `backup/stock_tv.dtb` and `backup/stock_tv.dts`.

Note from execution: busybox `tar` and `cp -r` cannot walk `/proc/device-tree` (it archives
only the directory). The working method is to fetch `/sys/firmware/fdt` directly, which is
the raw DTB, then `dtc -I dtb -O dts`. Keep that as the documented DT dump method.

Recreate the helper environment first: `/tmp/opencode/pwnlg/venv` with paramiko, or plain
`ssh` with password auth.

Kernel and platform:
- `uname -a`, `/proc/version` (includes compiler string), `/proc/cpuinfo`, `nproc`,
  `/proc/meminfo`, `free -m`
- `/proc/config.gz` greps: `CONFIG_MODULES`, `CONFIG_MODULE_SIG_FORCE`, `CONFIG_KEXEC`,
  `CONFIG_KEXEC_FILE`, `CONFIG_KEXEC_IMG`, `CONFIG_PSTORE`, `CONFIG_PSTORE_RAM`,
  `CONFIG_ION`, `CONFIG_DMABUF_HEAPS`, `CONFIG_DRM`, `CONFIG_FB`, `CONFIG_ANDROID_BINDERFS`,
  `CONFIG_ANDROID_BINDER_IPC`, `CONFIG_CGROUP`, `CONFIG_NAMESPACES`, `CONFIG_SECCOMP`

Device nodes:
- `/dev/ion`, `/dev/dri/card0` or `renderD128`, `/dev/fb0` through `/dev/fb3`
- `/proc/devices`, `ls /dev | grep -iE "binder|ashmem|ion|dri|fb|mali"`
- `ls /sys/class/net` (wired debug path depends on this), driver name from `/proc/net/dev`
- `lsmod` to see how `mali_kbase` is loaded and what owns display (`videooutputd`)

Device tree:
- `/proc/device-tree` presence
- `dtc -I fs -O dts /proc/device-tree -o stock_tv.dts`, then compile to `stock_tv.dtb`

Storage and crash dumps:
- `df -h` for `/var`, `/var/lib/webosbrew`, `/tmp`, `/media/developer`; target about 3 GB
  free persistent ext4 for Android staging
- Partition map for `/dev/mmcblk0p*`, including `p15/p16` (kernel), `p27` (rootfs squashfs),
  `p51` (snapshot resume), and the regions behind `wdtlog=dump@1M` and `mmcoops=dump`
- `cat /proc/cmdline` kept as reference for the Android cmdline diff

Deliverables: `phase0-survey.txt`, `stock_tv.dts`, `stock_tv.dtb`, partition map table.

Gate G0: we know arch, RAM, KEXEC support, ION presence, DRM node names, Ethernet driver,
and crash dump offsets. If `CONFIG_KEXEC` and `CONFIG_KEXEC_FILE` are both absent, bare
metal is unreachable on this firmware and we say so instead of building something slower.

---

## Phase 0.5: USB stick verification (needs TV on and the stick plugged)

This is a gate, not a nice-to-have, because the whole storage design depends on it.

Checks, all read-only:
- Plug the stick into a specific port and record which port. Front ports are easier to reach
  for bring-up iterations
- `ls /dev/sd*`, `cat /proc/partitions`, `ls /sys/class/net` unaffected, `mount` output to see
  how webOS mounts USB drives and what fstypes it accepts
- Confirm webOS can mount FAT32 or exFAT on partition 1. If webOS only mounts FAT32, use
  FAT32 and accept the 4 GB single-file limit by splitting the squashfs image into parts
- Write and read back a 200 MB test file on partition 1 to measure sustained throughput, and
  time a `dd` read so we know the boot cost before committing to the stick
- Confirm the stick's PARTUUID or serial is stable across reboots and across replugging into
  the same port
- Confirm Android's kernel build will see it: enable `CONFIG_USB_STORAGE`, SCSI, and the host
  controller support in our build. Stock USB is present (`usbcore.wisa` in the cmdline), so
  the host side works
- Confirm webOS does not auto-mount or auto-index the ext4 partition, and that its media
  scanner does not crawl the FAT partition while Android is running

Gate G0b: stick mountable by webOS on partition 1, throughput measured, device naming stable,
Android kernel USB storage support enabled. Nothing downstream is attempted before this passes.

## Phase 0.6: optional UART hunt

Open the chassis only if we want it. Look for TX/RX pads or a header on the O20B0
mainboard, 115200 8N1, level-safe (no 5V tolerance assumptions). Not a gate, not required,
and nothing blocks on it. Software recovery plus LG dumps carry the risk.

---

## Phase 1: kernel source and reproducible build

Status: DONE 2026-11-02. Findings in `phase1-findings.md`, recipe in `phase1-build.sh`.
Source came from the LG portal release `osSeq=511222` file 2 for `OLED55CX6LA`, labelled
"webOS 5.0 JO 2.0". Kernel `linux-4.4-lg115x` built with `lg1k_defconfig` using LG's bundled
aarch64 gcc 6.2 toolchain, producing a 13.9 MB `Image`. `mali_kbase.ko` and
`dma_buf_unified.ko` built against it. Two fixes were needed and are recorded in the recipe:
the `yylloc` double definition in kernel 4.4 host `dtc`, and LG's wrapper Makefile with a
broken `KCONFIG_CONFIG` reference that resolves to `/config_data.gz`.

Caveat worth keeping in front of everyone: the published release is JO 2.0 from 2022, our
firmware is 04.64.00 built in 2026. Base version `4.4.84` and platform `lg115x` /
`o20_pioneer` match, but driver revisions should be compared against the TV's
`/proc/config.gz` when it is reachable. Our build uses gcc 6.2 while the running kernel used
gcc 8.2, and our release string lacks LG's `-219.jcl4tvmr.6` suffix. That is acceptable
because we boot our own kernel, but modules built here will not load into the stock kernel.

What Phase 1 actually established:

1. Kernel source and toolchain obtained and built successfully. Reproducible build works.
2. `drivers/android/binder.c` and `drivers/staging/android/ashmem.c` exist in this tree, so
   binder and ashmem can be enabled in our kernel build even though stock config has them off.
3. `lg1k_defconfig` already carries `CONFIG_ANDROID=y`, `CONFIG_ION=y`, `CONFIG_ION_LG1K=y`,
   `CONFIG_MODULES=y`, `CONFIG_KEXEC=y`, `CONFIG_USB_STORAGE=y`, `CONFIG_FB=y`.
4. Allocator truth: LG's ION registers only `system` and `system contig` heaps, and the
   comment says memory separation happens in the bootloader. LG's GPU-facing allocator is
   `drivers/base/dma_buf_unified`, a misc device with alloc, import, status and sync ioctls
   that exports dma-buf fds. `mali_kbase` imports buffers via `dma_buf_get(fd)` and stores
   them as `imported.umm.dma_buf`. So gralloc allocates through `/dev/dma_buf_unified` and
   hands out the exported fd. Fallback, if that node is unavailable or restricted: register a
   carveout heap in our kernel build over the DT reserved regions (`0x33800000`, 1.24 GB, and
   `0xa9800000`, 360 MB) and allocate through ION `CARVEOUT`.
5. GPU coherence: kernel kbase references Mali-G51/G71/G72, `libmali.so.0.1` references
   `bifrost` and Mali-G51. Kernel driver and userspace DDK line up.
6. Vendor HAL reuse: no LG Android TV firmware exists on the `lg1k` / LG1212 / O20 platform as
   far as we can tell. There is no vendor gralloc, hwcomposer or audio HAL to lift. Our own
   HALs are required, with gralloc built on `dma_buf_unified`. That is a real estimate, not a
   shortcut.
7. `kexec_load` is the available interface. Android DTB is built from the LG source tree and
   passed explicitly.

Deliverables produced: kernel build recipe, GPU module build, DTB dump and decompile, vendor
firmware finding. Still owed: `android.cfg` config fragment, gralloc constraint table for
`dma_buf_unified`, DTB build recipe with Android additions.

Gate G1: reproducible stock kernel build with matching vermagic, and the heap map exists.
If vermagic does not match, nothing downstream is attempted.

---

## Phase 2: Android kernel and kexec staging

Kernel changes on top of LG source, per Phase 0 findings:
- Binder IPC built-in, `CONFIG_ANDROID_BINDER_IPC=y` plus `CONFIG_ANDROID_BINDERFS=y`, and
  `CONFIG_ASHMEM=y`. Stock has none of these, and modules are only a fallback.
- LG's ION kept (`CONFIG_ION=y`, `CONFIG_ION_LG1K=y`) as the fallback allocator path, plus
  LG's `drivers/base/dma_buf_unified` built into the Android kernel as the primary allocator
  path, which is what gralloc allocates through and what mali_kbase imports
- Android's legacy ION gralloc path only as the fallback, since LG's ION exposes just
  `system` and `system contig` heaps and the stock config has no dma-buf heaps
- mali kbase kept as a platform device, with cmdline `hma=` and `lg1k.` parameters intact
  and the DT `reserved-memory` carveouts preserved. There is no DT GPU node, so kbase probes
  through LG's platform device code, not through the device tree.
- `CONFIG_PSTORE` plus `CONFIG_PSTORE_RAM` enabled in our build. Stock has no pstore, so
  panic traces otherwise rely on LG's dump drivers plus our log directory.
- LG's `mmcoops` and `wdtlog` drivers carried into the Android build so crash dumps still
  land somewhere webOS can read after a reboot.
- Framebuffer console and `CONFIG_FB` kept, no DRM, since stock has no DRM at all.
- Watchdog handled so a kexec handoff does not trip a hardware reset.
- DTV and CEC drivers kept for the later tuner phase, unused for now.
- SELinux is entirely ours to configure, since the webOS kernel exposes no SELinux interface.
  Permissive through Phases 2-4, then denial collection, then enforcing with custom policy.

Android cmdline versus stock: keep `hma=`, `lg1k.use_vmap`, `lg1k.o20_*`, `cma_on`,
`vmalloc=`, `devtmpfs.mount=1`, `console=ttyAMA0`. Drop `resume=`, `snapshot`, `debugMode=`,
`sbkey=`, `portProtection`, `ToolOpt`, `modelopt`, `hwopt`, `serialNum`, `ethaddr`,
`lg1k.adc`, and the webOS-only root/squashfs arguments. Add Android's own root arguments
pointing at the stick by PARTUUID, never at `/dev/sdXN`, because USB enumeration order is not
stable. The system image mounts read-only as squashfs and the ext4 partition mounts as
`/data`.

Storage design, revised: the Android footprint lives on a USB stick, not on TV flash.

Requirements for the stick:
- 8 GB or more. Usable budget: about 2 GB system image, 2 GB `/data`, 50 MB images plus
  logs, rest spare for build iterations
- USB 3.x stick with honest sustained throughput. Boot reads the system image over USB, so a
  slow stick turns boot into several minutes. Avoid no-name sticks, fake capacity is common
- Two partitions, because webOS and Android need different filesystems:
  - partition 1, FAT32 or exFAT, mounted by webOS for staging, logs and the webOS kernel
    copy. webOS media/USB mounting typically supports FAT and NTFS, not ext4, so the
    webOS-visible half must not be ext4
  - partition 2, ext4 with a journal, mounted only by Android as `/data`. webOS will not
    mount it, which is exactly what we want: webOS never touches Android state
- Stable device naming. USB enumeration order can shift, so Android uses a PARTUUID or disk
  serial in its `root=` and `/data=` arguments rather than `/dev/sda1`
- The stick stays in a specific port. Mark it, and record the port, because enumeration and
  the PARTUUID depend on which port it lands in

Layout on partition 1 (webOS-visible, FAT/exFAT):
- `pwnandroid/images/` kernel, initramfs, rootfs squashfs, DTB, `manifest.sha256`
- `pwnandroid/logs/` written by Android with `O_SYNC`, readable from webOS after a reboot
- `pwnandroid/webos-kernel/` copy used by `pwnback-to-webos`
- `pwnandroid/state/` last boot outcome, guard flag, version stamps

Layout on partition 2 (Android-only, ext4): mounted as `/data`.

What this changes operationally:
- Images are copied from the PC onto the stick over the network, so the TV's 481 MB of free
  `/var` is never used for Android storage at all
- Android mounts the stick's squashfs system image read-only instead of unpacking a rootfs
  into RAM, which frees RAM for ART and SurfaceFlinger
- Pulling the stick makes Android unavailable, and webOS keeps booting normally. That is the
  revertible state, and it means no TV partition ever holds Android bits
- `pwnandroid.sh` refuses to boot if the stick is missing, the manifest does not verify, or
  the guard flag says the last boot failed hard

`pwnandroid.sh` pre-flight guards:
- Android image checksums valid
- Log directory writable
- Previous boot logged a hard failure unless the operator cleared the guard
- Refuses to boot if the stick is missing or the manifest does not verify, and refuses to
  touch any TV flash partition. All Android bits live on the stick

`pwnandroid.sh` boot: `kexec -l <image> --dtb=<dtb> --append="<android cmdline>"` then
`kexec -e`.

`pwnback-to-webos`: kexec the staged webOS kernel with the stock cmdline.

Round-trip test order: Android boots to init plus sshd with no graphics first. Graphics is
only attempted after that passes. This separates kernel bring-up from gralloc risk.

Gate G2: Android boots to init plus sshd over Ethernet via kexec, and returns to webOS
cleanly, repeatedly.

Gate G3: a deliberate hang plus power cycle leaves readable logs in the shared directory
and readable LG `wdtlog`/`mmcoops` dumps from webOS. Only after this do we consider an
auto-boot hook, and it stays flag-gated.

---

## Phase 3: AOSP build, TV-shaped

Build host requirement: about 100 GB free on an SSD and 16 GB+ RAM on the Linux box. Full
AOSP builds take hours. Nothing builds on the TV.

Target: AOSP 13 LTS arm64. Custom device folder `device/switchboy/pwnlg` with board config
pointing at our kernel and DTB.

Trimmed configuration:
- No camera, GPS, sensors, telephony, Bluetooth audio stack initially
- Ethernet enabled, WiFi MT7668 deferred
- Leanback launcher as the UI, TV defaults
- SELinux permissive through Phases 2-4, then `auditonly` denial collection, then a custom
  sepolicy for dropbear, the logging daemon and the HALs. Dropbear gets its own init
  context, not a stock shell domain, because pty and socket binds are what typically get
  denied when enforcing starts.

Deliverables: device folder, build recipe, trimmed manifest, sepolicy stubs, squashfs system
image and initramfs written onto the stick's FAT partition by the staging script.

Gate G3.5: rootfs plus initramfs build reproducibly on the PC and boot into init under the
Android kernel (already covered by G2's on-device test).

---

## Phase 4: graphics, audio and input (make-or-break)

Graphics:
- `mali_kbase.ko` loads in the Android kernel as LG's platform device, with cmdline `hma=`
  regions and DT `reserved-memory` carveouts intact. Built from LG source in Phase 1, and it
  matches the userspace DDK on this GPU (G51 / Bifrost)
- gralloc allocates through LG's `dma_buf_unified` misc device, using its alloc and import
  ioctls, and hands out the exported dma-buf fd, which is what `mali_kbase` imports as
  `imported.umm.dma_buf`. This replaces the earlier ION heap-alignment plan, because LG's ION
  on this platform only exposes `system` and `system contig` heaps
- Fallback allocator if `/dev/dma_buf_unified` turns out to be unavailable or restricted:
  register a carveout heap in our kernel build over the DT reserved regions and allocate
  through ION `CARVEOUT`
- hwcomposer targets the framebuffer stack (`/dev/fb0`, `/dev/dc_fbdev`), since the stock
  kernel has no DRM at all. Mode set, vsync, hotplug and HDMI input events all go through fb
- EGL/GLES stack validated against `libmali.so.0.1` plus `libEGLfk.so` semantics
- No vendor HALs exist for this platform, so gralloc, hwcomposer and audio HAL are ours to
  write. Expect this to be the bulk of the work, not a port job

Audio:
- ALSA HAL over the stock sound stack, HDMI audio output included

Input:
- evdev input HAL for the LG remote, keyboard-style event mapping
- HDMI CEC deferred with the tuner phase

Scope: HDMI inputs only. No DTV tuner in this phase.

Proprietary blobs (`libmali`, LG display and audio libraries, LG drivers) stay on disk and
never enter the repo. A local build script references them.

Gate G4: gralloc allocations accepted by mali_kbase. This is the single item that decides
whether the project survives. If it fails, we report it plainly rather than falling back to
emulation, which is explicitly out of scope.

Gate G5: SurfaceFlinger plus HDMI input on screen, audio HAL alive, Android TV apps usable.

---

## Phase 5: command-line workflow (the product surface)

1. Stick plugged into the recorded port, TV booted into webOS
2. `ssh -p 22 -i pwn_ed25519 root@<TV-IP>` into webOS
3. `pwnandroid.sh --check`: stick present, manifest verified, guard state, last boot outcome,
   measured boot cost, webOS mount state for the FAT partition
4. `pwnandroid.sh`: unmounts the stick cleanly in webOS, then `kexec -l` with `--dtb=` and
   `--append=`, then `kexec -e`
5. `ssh -p 22 -i pwn_ed25519 root@<TV-IP>` into Android dropbear, or adb on 5555
6. `pwnback-to-webos`: kexec back, or power cycle if Android hangs hard. The stick stays put,
   so logs survive either way
7. Reboot into webOS, read `pwnandroid/logs/` on the stick to see exactly how far Android got

Deliverables: `pwnandroid.sh`, `pwnback-to-webos`, `phase0-survey.sh`, stick layout and
formatting recipe, guard logic, `pwnAndroidGuide.md` written noob-friendly like
`pwnPatchGuide.md`.

---

## Phase 6: verification and rollback

- Repeated Android boot and return cycles with no partition writes anywhere
- webOS persistence unaffected: `10-telemetry-block` still runs on webOS boot, spyware
  processes stay at zero, root SSH still comes up
- Log boundary test: kill hwcomposer on purpose, power cycle, verify the failure log is
  readable from webOS
- Early-SSH test: deliberately broken gralloc, verify dropbear still gives a shell
- Crash dump test: force a kernel panic, verify LG `wdtlog`/`mmcoops` regions are readable
  after reboot into webOS
- Guard test with a missing stick: unplug the stick, confirm `pwnandroid.sh` refuses to boot
- Guard test with a corrupt image: break a checksum in the manifest, confirm refusal
- Stick port discipline: replug into a different port, confirm PARTUUID-based boot still
  resolves and `/dev/sdXN` assumptions are nowhere in the cmdline or scripts
- Clean unmount test: confirm webOS unmounts the FAT partition before kexec, so a hard hang
  cannot leave dirty FAT state behind

Gate G6: all of the above pass, repeatedly, with no partition writes.

---

## Phase 7: tuner and Live TV (deferred)

Needs a Tuner HAL mapped onto LG's proprietary DTV driver, plus CEC and the Live TV app
path. This is a separate RE project with its own plan. Do not start it before G5 passes.

---

## Milestone gates summary

| Gate | Pass condition | Blocks |
|---|---|---|
| G0 | DONE 2026-11-02. Survey complete: aarch64 Cortex-A55, 3 GiB RAM, `CONFIG_KEXEC=y`, `CONFIG_ION_LG1K=y`, framebuffer stack (no DRM), `snps,dwmac` Ethernet, LG dump params, DTB dumped | Phase 1 |
| G0b | USB stick verified: webOS mounts partition 1 (FAT/exFAT), throughput measured, PARTUUID stable across reboots and replug, Android kernel USB storage enabled, ext4 partition untouched by webOS | Phases 2-5 |
| G1 | DONE 2026-11-02. Kernel and GPU driver build reproducibly from LG source. Deviations noted: gcc 6.2 versus stock 8.2, release string lacks LG suffix, published release is JO 2.0 versus our 2026 firmware | Phases 2-3 |
| G2 | Android boots to init plus sshd via kexec and returns to webOS | Graphics work |
| G3 | Hang plus power cycle leaves readable logs plus LG crash dumps from webOS | Any auto-boot hook |
| G4 | gralloc allocations via `dma_buf_unified` accepted by mali_kbase | hwcomposer and UI |
| G5 | SurfaceFlinger plus HDMI on screen, audio alive, apps usable | Tuner phase |
| G6 | Repeated cycles, no partition writes, webOS unaffected | Shipping anything persistent |

---

## Do-not-do list

- Never write to kernel, rootfs or tvservice partitions. That brick is not recoverable.
- Never reinstall the Developer Mode app while rooted, never reboot while it is installed.
- Never launch Android without the pre-flight guards, and never bypass vermagic with
  `--force-vermagic` in place of a real toolchain match.
- Never put Android storage on TV flash partitions. The stick is the storage. `/var` holds
  webOS data and must stay untouched by Android bits.
- Never let webOS mount the Android ext4 partition, and never let Android mount webOS
  partitions read-write.
- Never address the stick as `/dev/sda1`. Always resolve it by PARTUUID or disk serial, and
  always plug it into the recorded port.
- Never leave the FAT partition mounted read-write in webOS across a kexec handoff.
- Never enable SELinux enforcing before denial collection is done.
- Never auto-boot Android before G3 passes.
- Do not push LG proprietary blobs to the public repo.
- Do not fall back to emulation if G4 fails. Emulation was ruled out by the operator.

---

## Open items, in order

1. An 8 GB USB stick, USB 3.x, honest capacity, plugged into a recorded port. This is now a
   prerequisite for every storage step, and Phase 0.5 verifies it on the TV
2. Wired Ethernet cable on the TV. `eth0` currently has no carrier, and it is the planned
   debug path, so bring-up needs a cable rather than Wi-Fi
3. TV reachable again, for the follow-ups listed in `phase1-findings.md`: full
   `/proc/config.gz` dump, stock versus published source config comparison, and whether
   `/dev/dma_buf_unified` exists on the running kernel
4. `android.cfg` config fragment plus the gralloc constraint table for `dma_buf_unified`
5. AOSP trim decisions, mainly to keep the squashfs system image under the FAT single-file
   limit if webOS only mounts FAT32
6. Optional internal UART pin hunt when the chassis is open
7. Build box with roughly 100 GB free on an SSD and 16 GB+ RAM for AOSP

---

## Honest risk statement

The plan is reachable, but the honest failure point is Gate G4. LG's GPU-facing allocator is
`dma_buf_unified`, and Android's gralloc has to be written against it by us, since no LG
Android TV firmware exists on this chipset family to lift HALs from. Everything before G4 is
plumbing we can verify safely. Everything after G4 depends on our HAL feeding `libmali` and
`mali_kbase` buffers they accept. If G4 fails, the truthful outcome is "bare-metal Android on
this firmware needs a vendor graphics HAL that LG does not publish", and we stop there.

The secondary constraint was storage, not graphics, and the USB stick resolves it. The
residual risks are operational rather than architectural: a slow stick makes every boot
iteration take minutes, FAT32 caps a single file at 4 GB so the system image may need
splitting, and FAT has no journal so a hard hang can lose the tail of a log. All three are
measured in Phase 0.5 before we sink hours into an AOSP build.
