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
| Phase 0 confirmed: `/var` has only 481 MB free | A full AOSP rootfs cannot live on disk. Compressed images in `/var`, unpacked into RAM by the Android initramfs, `/data` in RAM during bring-up. |
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

---

## Recovery layers, in order of reliability

1. LG kernel crash dumps: `wdtlog=dump@1M`, `mmcoops=dump`. Survive a kernel panic with
   no userspace alive. Readable from webOS after reboot. Partition offsets confirmed in
   Phase 0.
2. Shared log directory: Android writes boot logs into
   `/var/lib/webosbrew/android/logs/`, which webOS can read after rebooting back.
   Files opened with `O_SYNC`, plus a periodic `sync` from the logging daemon, so a freeze
   does not leave truncated or zero-byte logs.
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

## Phase 0.5: optional UART hunt

Open the chassis only if we want it. Look for TX/RX pads or a header on the O20B0
mainboard, 115200 8N1, level-safe (no 5V tolerance assumptions). Not a gate, not required,
and nothing blocks on it. Software recovery plus LG dumps carry the risk.

---

## Phase 1: kernel source and reproducible build

1. Pull LG kernel source for OTAID `HE_DTV_W20O_AFABABAA`, firmware 04.64.00, from the LG
   open-source portal. GPL release, matching this firmware.
2. Confirm the source version matches `/proc/version` exactly.
3. Build the stock config unchanged with the toolchain LG's build docs specify. Phase 0 says
   the kernel was built with gcc 8.2.0, so an aarch64 gcc 8.2 cross toolchain is the target.
   Diff the resulting `vermagic` against `/proc/version`. A clean match means out-of-tree
   modules load without `--force-vermagic`. A mismatch means ABI problems and the project
   stops here honestly.
4. Read LG's ION driver source, specifically `CONFIG_ION_LG1K`, and extract heap IDs, heap
   masks and named custom heaps. `mali_kbase.ko` references `ion_alloc`, `ion_map`,
   `ion_flags`, `ion_id`, `ion_debugfs_init` and `tiler_heap_free`, so the tiler heap needs
   explicit handling in the mapping table.
5. Vendor firmware search, narrowed by Phase 0: look for LG builds on the `lg1k` / LG1212
   platform that ship Android TV, not any LG Android TV. If such a build exists, reuse its
   gralloc, hwcomposer and audio HAL plus its kernel config that already enables Android
   options. If nothing on this platform ships Android, report that and write our own fb-based
   HALs instead of forcing a mismatched vendor HAL onto this chip.
6. Decide `kexec_file_load` versus `kexec_load`, and build the Android DTB from the LG
   source tree rather than trusting kexec defaults.

Deliverables: kernel build recipe, `android.cfg` config fragment, ION heap-to-gralloc
mapping table, DTB build recipe, vendor-firmware finding.

Gate G1: reproducible stock kernel build with matching vermagic, and the heap map exists.
If vermagic does not match, nothing downstream is attempted.

---

## Phase 2: Android kernel and kexec staging

Kernel changes on top of LG source, per Phase 0 findings:
- Binder IPC built-in, `CONFIG_ANDROID_BINDER_IPC=y` plus `CONFIG_ANDROID_BINDERFS=y`, and
  `CONFIG_ASHMEM=y`. Stock has none of these, and modules are only a fallback.
- LG's ION kept (`CONFIG_ION=y`, `CONFIG_ION_LG1K=y`) as the allocator path. No dma-buf
  heaps exist in stock, so Android's legacy ION gralloc path is the target.
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
`lg1k.adc`, and the webOS-only root/squashfs arguments.

Staging layout in `/var/lib/webosbrew/android/`, sized to the 481 MB of free `/var`:
- `images/` holding compressed kernel, initramfs, rootfs squashfs and DTB, target about
  250 MB total
- `logs/` written with `O_SYNC`
- `webos-kernel/` copy used by `pwnback-to-webos`
- `images/manifest.sha256`, so a corrupt stage never launches
Android's rootfs is unpacked into RAM by the initramfs after webOS is gone, and `/data`
stays in RAM during bring-up. That is what makes the storage limit workable: disk holds
compressed images, RAM holds the running system.

`pwnandroid.sh` pre-flight guards:
- Android image checksums valid
- Log directory writable
- Previous boot logged a hard failure unless the operator cleared the guard
- Refuses to touch any partition other than the staging directory

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

Deliverables: device folder, build recipe, trimmed manifest, sepolicy stubs, rootfs build
into the staging directory.

Gate G3.5: rootfs plus initramfs build reproducibly on the PC and boot into init under the
Android kernel (already covered by G2's on-device test).

---

## Phase 4: graphics, audio and input (make-or-break)

Graphics:
- `mali_kbase.ko` loads in the Android kernel as LG's platform device, with cmdline `hma=`
  regions and DT `reserved-memory` carveouts intact
- gralloc allocates through LG's ION driver (`CONFIG_ION_LG1K`) using the exact heap IDs and
  masks read from source in Phase 1, and those buffers must be accepted by `libmali.so.0.1`
- `tiler_heap` handled explicitly in the mapping table
- hwcomposer targets the framebuffer stack (`/dev/fb0`, `/dev/dc_fbdev`), since the stock
  kernel has no DRM at all. Mode set, vsync, hotplug and HDMI input events all go through fb
- EGL/GLES stack validated against `libmali.so.0.1` plus `libEGLfk.so` semantics

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

1. `ssh -p 22 -i pwn_ed25519 root@<TV-IP>` into webOS
2. `pwnandroid.sh --check`: image checksums, HAL presence, log directory, guard state, last
   boot outcome
3. `pwnandroid.sh`: kexec into Android
4. `ssh -p 22 -i pwn_ed25519 root@<TV-IP>` into Android dropbear, or adb on 5555
5. `pwnback-to-webos`: kexec back, or power cycle if Android hangs hard
6. Reboot into webOS, then read `/var/lib/webosbrew/android/logs/` to see exactly how far
   Android got

Deliverables: `pwnandroid.sh`, `pwnback-to-webos`, `phase0-survey.sh`, staging layout,
guard logic, `pwnAndroidGuide.md` written noob-friendly like `pwnPatchGuide.md`.

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
- Guard test: corrupt a staged image, confirm `pwnandroid.sh` refuses to boot it

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
| G1 | Reproducible stock kernel build, vermagic match, ION heap map extracted | Phases 2-3 |
| G2 | Android boots to init plus sshd via kexec and returns to webOS | Graphics work |
| G3 | Hang plus power cycle leaves readable logs plus LG crash dumps from webOS | Any auto-boot hook |
| G4 | gralloc ION allocations accepted by mali_kbase | hwcomposer and UI |
| G5 | SurfaceFlinger plus HDMI on screen, audio alive, apps usable | Tuner phase |
| G6 | Repeated cycles, no partition writes, webOS unaffected | Shipping anything persistent |

---

## Do-not-do list

- Never write to kernel, rootfs or tvservice partitions. That brick is not recoverable.
- Never reinstall the Developer Mode app while rooted, never reboot while it is installed.
- Never launch Android without the pre-flight guards, and never bypass vermagic with
  `--force-vermagic` in place of a real toolchain match.
- Never enable SELinux enforcing before denial collection is done.
- Never auto-boot Android before G3 passes.
- Do not push LG proprietary blobs to the public repo.
- Do not fall back to emulation if G4 fails. Emulation was ruled out by the operator.

---

## Open items, in order

1. Wired Ethernet cable on the TV. `eth0` currently has no carrier, and it is the planned
   debug path, so bring-up needs a cable rather than Wi-Fi
2. LG kernel source for firmware 04.64.00 / `HE_DTV_W20O_AFABABAA`
3. aarch64 gcc 8.2 cross toolchain to match `/proc/version`, plus LG's build docs
4. `lg1k` / LG1212 Android TV firmware check for vendor HAL reuse (narrowed by Phase 0)
5. AOSP trim decisions so the compressed rootfs fits inside roughly 250 MB of `/var`
6. Optional internal UART pin hunt when the chassis is open
7. Build box with roughly 100 GB free on an SSD and 16 GB+ RAM for AOSP

---

## Honest risk statement

The plan is reachable, but the honest failure point is Gate G4. ION heap alignment with
`mali_kbase` plus `libmali` is the whole ballgame, and vendor HAL reuse may or may not be
available for the `lg1k` platform. Everything before G4 is plumbing we can verify safely.
Everything after G4 depends on LG's proprietary graphics stack cooperating with Android's
allocator. If G4 fails, the truthful outcome is "bare-metal Android on this firmware is not
achievable without LG's own Android TV HALs for this chip", and we stop there.

The secondary constraint is storage, not graphics. `/var` has 481 MB free, so the whole
Android footprint must be compressed images plus RAM unpacking. If a usable trimmed AOSP
will not fit that budget, the honest outcome is "this TV can boot Android only with a
heavily trimmed build", and that trim must be decided before we sink hours into an AOSP
build that cannot land.
