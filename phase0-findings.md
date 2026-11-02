# Phase 0 survey findings (2026-11-02)

Run against the rooted OLED55CX6LA over root SSH, read-only. Raw capture kept in
`backup/phase0-survey.raw` (gitignored, contains serial and MAC addresses).
Device tree binary kept as `backup/stock_tv.dtb` plus `backup/stock_tv.dts`. Note that both
contain the stock `chosen.bootargs`, which includes the serial number and MAC addresses, so
they stay gitignored and must be sanitized before any public release.

## Platform

| Item | Value |
|---|---|
| Kernel | Linux 4.4.84-219.jcl4tvmr.6, SMP PREEMPT, built with gcc 8.2.0 |
| Arch | aarch64 |
| SoC | `lge,lg1212` / `lge,lg1k`, cmdline `chip=O20B0`, model string "LG Electronics, DTV SoC LG1212 (AArch64)" |
| CPUs | DTB declares 4x Arm Cortex-A55 (`cpu@0`..`cpu@3`), `nproc` reports 3 online |
| RAM | `MemTotal` 2680936 kB, `MemAvailable` about 450 MB while webOS runs, physical region 3 GiB (`memory` reg size 0xc0000000) |
| Swap | 614 MB present |
| CMA | `CmaTotal` 1245184 kB, `CmaFree` 18 MB while webOS runs |
| Display path | no DRM (`CONFIG_DRM is not set`). Framebuffer nodes: `/dev/fb`, `/dev/fb0`..`/dev/fb3`, `/dev/dc_fbdev` |
| GPU | `/dev/mali0`, LG's kbase probed as a platform device using cmdline `hma=` regions, not via DT (no GPU node in DTB) |
| ION | `/dev/ion` present, `CONFIG_ION=y` plus `CONFIG_ION_LG1K=y` |
| Binder / ashmem | not registered, no nodes (`CONFIG_ANDROID_BINDER_IPC is not set`) |
| Ethernet | `/sys/class/net/eth0` exists, DTB `compatible = "lge,lg115x-dwmac", "snps,dwmac"` plus `ethernet-phy-id0044.1400`. Currently NO-CARRIER (TV is on Wi-Fi), so the debug path needs a cable |
| SELinux | webOS kernel has no SELinux interface at all |
| Crash dumps | cmdline carries `mmcoops=dump`, `wdtlog=dump@1M`, `snapshot resume=/dev/mmcblk0p51` |
| UART | `console=ttyAMA0,115200n81` present in cmdline and DTB `chosen.bootargs` |

## Kernel config facts that matter

Positive:
- `CONFIG_KEXEC=y`, `CONFIG_KEXEC_CORE=y` (no `CONFIG_KEXEC_FILE`)
- `CONFIG_MODULES=y`, and `CONFIG_MODULE_SIG is not set`, so unsigned modules load
- `CONFIG_ION=y`, `CONFIG_ION_LG1K=y`
- `CONFIG_FB=y`, `CONFIG_CMA=y`, `CONFIG_EXT4_FS=y`, `CONFIG_SQUASHFS=y`, `CONFIG_TMPFS=y`, `CONFIG_NAMESPACES=y`

Negative:
- `CONFIG_DRM is not set`
- `CONFIG_ANDROID_BINDER_IPC is not set`, no binderfs, no ashmem
- `CONFIG_PSTORE is not set`
- `CONFIG_SECCOMP is not set`
- No dma-buf heap support in the stock config

## Storage reality check, which changes the staging design

| Location | Free |
|---|---|
| `/var` (`mmcblk0p55`, ext4 overlay) | 481 MB |
| `/tmp` tmpfs | 1.3 GB, RAM backed |
| `/mnt/lg/appstore` (`mmcblk0p56`) | 487 MB, LG app store data, do not use |
| `/var/lib/webosbrew` | 32 KB used, lives inside `/var` |

A full AOSP rootfs does not fit in persistent free space. So Android must boot with
compressed images stored in `/var`, decompressed into RAM by the Android initramfs once
webOS is gone, and `/data` stays in RAM for the bring-up phase.

## Device tree facts

- `chosen.bootargs` holds the whole stock cmdline, including LG-specific parameters
- `reserved-memory` declares two regions that belong to LG's graphics and kernel drivers:
  - `kdrv_buffer1@1` at `0x33800000`, size `0x4c800000` (about 1.24 GB), `no-map`
  - `kdrv_buffer2@2` at `0xa9800000`, size `0x16800000` (about 360 MB), `no-map`
  These are the CMA and HMA carveouts referenced by the cmdline (`cma_on`,
  `hma=856M@0x47800000;360M@0xa9800000`). Our Android kernel must reuse them rather than
  invent new regions.
- Ethernet controller and PHY are declared in DT, so wired Ethernet bring-up is standard
  `snps,dwmac` work with LG's variant compatible string
- There is no GPU node in the DT. LG's kbase probes via platform device plus cmdline
  `hma=` and `lg1k.` parameters, so the Android cmdline must keep those LG parameters

## What this amends in the plan

1. Display target is framebuffer (`/dev/fb0` and `dc_fbdev`), not DRM. The staged blob
   names hinted at DRM, but the stock kernel has no DRM at all. Android hwcomposer must
   be fb-based.
2. Binder and ashmem come from our own kernel build, built-in (`CONFIG_ANDROID_BINDER_IPC`,
   `CONFIG_ANDROID_BINDERFS`, `CONFIG_ASHMEM`), not as out-of-tree modules. Module loading
   stays available as a fallback because module signing is off.
3. Gralloc targets LG's ION (`CONFIG_ION_LG1K`), not dma-buf heaps, since the stock config
   has no dma-buf heap support. Android's legacy ION gralloc path is the target.
4. `CONFIG_PSTORE` is absent in stock, so panic traces rely on LG's `mmcoops`/`wdtlog`
   drivers plus our log directory. We enable pstore in our Android kernel build, and carry
   LG's mmcoops/wdtlog drivers into it so dumps still land where webOS can read them.
5. Storage design revised: an 8 GB USB stick becomes the Android storage location, because
   `/var` has only 481 MB free. Two partitions: FAT32 or exFAT for images, logs and the webOS
   kernel copy (webOS-visible), ext4 for Android `/data` (Android-only). Android mounts the
   squashfs system image read-only from the stick instead of unpacking a rootfs into RAM.
   Pulling the stick removes Android and changes nothing on TV flash.
6. `kexec_load` is the available interface (no `CONFIG_KEXEC_FILE`), so the DTB must be
   passed explicitly with `--dtb=`, using the dump we already have.
7. Android cmdline keeps `hma=`, `lg1k.` parameters, `cma_on`, `vmalloc=`, `console=ttyAMA0`
   and drops `resume=`, `snapshot`, `debugMode=`, `sbkey=`, `portProtection`, `ToolOpt`,
   `serialNum`, `ethaddr`, `lg1k.adc`.
8. CPU target stays arm64 for Cortex-A55 with NEON, AES, SHA1/SHA2 and atomics. Four cores
   declared, three online.
9. Vendor HAL reuse search narrows to LG builds on the `lg1k` / LG1212 platform, which is a
   much tighter search than "any LG Android TV".

## Still needed before Phase 1

- An 8 GB USB stick, USB 3.x with honest sustained throughput, plugged into a recorded port.
  Phase 0.5 verifies webOS mount support, throughput and stable device naming
- Wired Ethernet cable on the TV, since `eth0` currently has no carrier and it is the
  planned debug path
- LG kernel source for firmware 04.64.00 on this OTAID, plus a gcc 8.2 aarch64 cross
  toolchain to match `/proc/version`
- AOSP trim decisions, mostly to keep the squashfs system image under the FAT 4 GB single-file
  limit if webOS only mounts FAT32

Note: the TV became unreachable over SSH at the end of the Phase 0 run (3 packets, 100%
loss). It was likely standby or Wi-Fi drop. Re-check before Phase 0.5.
