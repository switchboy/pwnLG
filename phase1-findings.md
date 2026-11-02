# Phase 1 findings (2026-11-02)

Kernel source obtained from LG's open source portal, built on the PC, GPU driver built
against it. Recipe in `phase1-build.sh`. Source tree and build output stay outside the
repo (`/tmp/opencode/pwnlg/lgsrc`), since LG packages are large and GPL-sized.

## What we got

Portal path that works: `POST /download/releaseFileDownloadUrl` with
`osSeq=511222&fileType=Op&fileIdx=2&modelName=OLED55CX6LA`, Referer set, returns a signed
S3 URL. `osSeq 511222` is the newest published release for this model, labelled
"webOS 5.0 JO 2.0" (notice dated 221228). File 2 of 3 is the SoC BSP:

- `JO-r3357_SoC/SoC_BSP_webOS_5.0.tar`, 642 MB
  - `GPL_2.0/kdriver.tar.gz`: kernel source `linux-4.4-lg115x.tgz`, bundled toolchain
    `aarch64-lg1k-linux-gnueabi-6.2-2018.08-x86_64.tar.gz`, LG kdriver sources with platform
    dirs including `o20_pioneer` and `o20_webos_udtv` (our chip)
  - `GPL_2.0/gpu.tar.gz`: Arm Midgard/Bifrost kbase source plus LG's `dma_buf_unified` driver
  - `GPL_2.0/firmware_vdec.tgz`: VDEC firmware with its own kernel (3.18-rc5) and toolchain
- `JO-r3357_SoC/o20_mt7668.tgz`: MT7668 WiFi driver source for our WLAN chip

## Build result

- Kernel: `lg1k_defconfig`, built directly in the tree, produced
  `arch/arm64/boot/Image`, 13.9 MB
  `Linux version 4.4.84 (gcc version 6.2.0) SMP PREEMPT`
- GPU modules against that kernel: `mali_kbase.ko` (15.6 MB) and `dma_buf_unified.ko`
  (326 KB), vermagic `4.4.84 SMP preempt mod_unload aarch64`

Two build fixes were needed, both documented in `phase1-build.sh`:
- Kernel 4.4 host `dtc` fails with modern binutils (`yylloc` defined twice). Fix is
  `extern YYLTYPE yylloc;` in `scripts/dtc/dtc-lexer.lex.c`
- LG's `kdriver/kernel/Makefile` wrapper has a broken `KCONFIG_CONFIG` reference that
  resolves to `/config_data.gz`, so the wrapper's `make` fails. Building the kernel tree
  directly works and is what we do

## Deviations from the running kernel, stated plainly

- The release corresponds to webOS 5.0 JO 2.0. Our firmware reports 04.64.00 built in April
  2026, so LG may have revised the kernel since this published release. Base version matches
  (`4.4.84`) and the platform matches (`lg115x`, `o20_pioneer` / `o20_webos_udtv`), but the
  full config and driver revisions should be compared against `/proc/config.gz` from the TV
  when it is reachable
- Our build uses LG's bundled gcc 6.2. The running kernel was built with gcc 8.2. This is
  fine because we boot our own kernel, and ARM64 module vermagic does not encode the compiler.
  It does mean modules built here will not load into the stock kernel, since the release
  string differs (`4.4.84` versus `4.4.84-219.jcl4tvmr.6`)
- Our kernel release lacks LG's `-219.jcl4tvmr.6` suffix. If we ever need stock-kernel module
  loading as a fallback, that suffix plus a matching compiler would have to be reproduced

## Allocator strategy, which is the important finding

The plan assumed ION heap alignment. The source says something better:

- LG's ION on this platform registers only two heaps, `system` and `system contig`, and the
  comment in `drivers/staging/android/ion/lg1k/lg1k_ion_dev.c` says memory separation is done
  by the bootloader. So ION here is not a GPU-facing allocator
- LG ships `drivers/base/dma_buf_unified`, a misc device named `dma_buf_unified` with
  `alloc` (contiguous and non-contiguous variants), `import`, `status`, `sync` ioctls, exporting
  dma-buf fds, with a 32-bit coherent DMA mask
- `mali_kbase` imports buffers through `dma_buf_get(fd)` and stores them as
  `imported.umm.dma_buf`, so any exported dma-buf fd works
- Therefore Android's gralloc HAL should allocate through `/dev/dma_buf_unified` and hand out
  the exported dma-buf fd. That is LG's own GPU-facing allocator, already used by webOS,
  instead of inventing ION heaps or dma-buf heap registration

Fallback if the device node turns out to be unavailable or restricted: register a carveout
heap in our kernel build pointing at the DT reserved regions (`0x33800000` size 1.24 GB,
`0xa9800000` size 360 MB), and allocate through ION `CARVEOUT`.

## GPU coherence check

`mali_kbase.ko` strings reference Mali-G51, G71, G72 plus Midgard parts, and
`libmali.so.0.1` strings reference `bifrost` and Mali-G51. So kernel driver and userspace DDK
line up on this GPU.

## Android kernel capability check from the source

- `drivers/android/binder.c` and `binder_trace.h` exist in this kernel tree, so binder can be
  enabled in our build even though the stock config has `CONFIG_ANDROID_BINDER_IPC` unset
- `drivers/staging/android/ashmem.c` exists
- `lg1k_defconfig` already has `CONFIG_ANDROID=y`, `CONFIG_ION=y`, `CONFIG_ION_LG1K=y`,
  `CONFIG_MODULES=y`, `CONFIG_KEXEC=y`, `CONFIG_USB_STORAGE=y`, `CONFIG_FB=y`, which lines up
  with the Phase 0 survey

## Vendor HAL reuse search, honest result

Searching for LG Android TV firmware on the `lg1k` / LG1212 / O20 platform found nothing.
LG's Android TV sets are not on this chipset family as far as we can tell. So there is no
vendor gralloc, hwcomposer or audio HAL to lift. The HALs have to be written by us, with
gralloc built on the `dma_buf_unified` interface described above. That is a real work
estimate, not a shortcut.

## Follow-ups that need the TV

The TV went unreachable during this phase (SSH timeout plus 100% ping loss). Recheck when it
is back on:
- Full `/proc/config.gz` dump, not the subset Phase 0 grepped. `CONFIG_DMA_SHARED_BUFFER` and
  `CONFIG_USB_STORAGE` were never checked in the stock config
- Whether `/dev/dma_buf_unified` exists on the running webOS kernel, and its permissions
- Whether the running kernel's GPU driver revision differs from this published source
