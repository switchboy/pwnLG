#!/bin/sh
# pwnLG Phase 1 build recipe: LG GPL kernel + GPU driver for the OLED CX (lg115x / O20)
# Run on the build PC. Sources and build output stay outside the repo.
#
# Fetch step (LG Open Source portal, no auth needed, POST to resolve an S3 URL):
#   curl -s -X POST https://opensource.lge.com/download/releaseFileDownloadUrl \
#     -d "osSeq=511222&fileType=Op&fileIdx=2&modelName=OLED55CX6LA" \
#     -H "Referer: https://opensource.lge.com/product/list?ctgr=005&subCtgr=006"
#   then curl -L -o jo2_2.tar.gz "<the returned data URL>"
# osSeq 511222 is the newest published release for OLED55CX6LA (webOS 5.0 JO 2.0).
set -eu

WORK=${WORK:-/tmp/opencode/pwnlg/lgsrc}
mkdir -p "$WORK"
cd "$WORK"

if [ ! -f jo2_2.tar.gz ]; then
  echo "fetch jo2_2.tar.gz from the LG portal first (see header comment)"
  exit 1
fi

tar -xf jo2_2.tar.gz
tar -xf JO-r3357_SoC/SoC_BSP_webOS_5.0.tar
cd webOS5.0_SIC_Opensource/GPL_2.0
tar -xf kdriver.tar.gz
tar -xf gpu.tar.gz

cd kdriver
tar -xf toolchain/aarch64-lg1k-linux-gnueabi-6.2-2018.08-x86_64.tar.gz
export PATH="$PWD/toolchain/aarch64-lg1k-linux-gnueabi-6.2-2018.08-x86_64/bin:$PATH"

# LG's wrapper Makefile has a broken KCONFIG_CONFIG reference (it resolves to
# /config_data.gz), so build the kernel tree directly instead of via kdriver/kernel.
# Kernel 4.4 host dtc fails with modern binutils: yylloc is defined twice. Patch it.
cd kernel/linux-4.4-lg115x
sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/' scripts/dtc/dtc-lexer.lex.c
make ARCH=arm64 CROSS_COMPILE=aarch64-lg1k-linux-gnueabi- lg1k_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-lg1k-linux-gnueabi- -j$(nproc) Image

# GPU: kbase plus LG's dma_buf_unified exporter, built against the kernel tree
# through gpu/linux, which symlinks to kdriver/kernel/linux-4.4-lg115x.
cd ../../../gpu/kernel
make
echo "kernel Image: $(ls -la "$WORK/webOS5.0_SIC_Opensource/GPL_2.0/kdriver/kernel/linux-4.4-lg115x/arch/arm64/boot/Image")"
echo "gpu modules:  $(ls -la "$WORK/webOS5.0_SIC_Opensource/GPL_2.0/gpu/result_kernel")"
