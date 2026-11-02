#!/bin/sh
# pwnLG Phase 0 survey — READ-ONLY. Nothing here writes to the TV or its partitions.
# Run as root over SSH. Output is captured to phase0-survey.txt for analysis.
sec() { echo "=== $1 ==="; }

sec "kernel"
uname -a
cat /proc/version

sec "cpu"
grep -E "CPU part|CPU implementer|processor|Features" /proc/cpuinfo | head -12
nproc

sec "memory"
grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|CmaTotal|CmaFree" /proc/meminfo

sec "cmdline"
cat /proc/cmdline

sec "config.gz presence"
ls -la /proc/config.gz 2>/dev/null || echo "NO /proc/config.gz"

sec "config greps"
zcat /proc/config.gz 2>/dev/null | grep -E \
  "CONFIG_KEXEC|CONFIG_MODULE|CONFIG_ION|CONFIG_DMABUF|CONFIG_PSTORE|CONFIG_DRM|CONFIG_FB|CONFIG_ANDROID_BINDER|CONFIG_CMA|CONFIG_CGROUP|CONFIG_NAMESPACES|CONFIG_SECCOMP|CONFIG_TMPFS|CONFIG_SQUASHFS|CONFIG_EXT4" | sort

sec "device nodes"
ls /dev 2>/dev/null | grep -iE "ion|binder|ashmem|dri|fb|mali|drm|gpu|kbd|input|evdev|cec|tuner|dtv" | sort

sec "proc devices"
cat /proc/devices

sec "drm + fb"
ls -la /dev/dri 2>/dev/null; ls -la /dev/fb* 2>/dev/null
ls /sys/class/drm 2>/dev/null

sec "gpu driver"
lsmod 2>/dev/null | head -25
ls -la /sys/class/misc 2>/dev/null | head -10

sec "network"
ls /sys/class/net 2>/dev/null
cat /proc/net/dev
ip link 2>/dev/null | head -12

sec "display stack owners"
for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null); \
  case "$c" in videooutputd*|*compositor*|*luna*|*WAM*|*surface*|*mali*) echo "$p $c $(grep ^Uid $p/status 2>/dev/null | awk '{print $2}')";; esac; done | head -12

sec "storage layout"
df -h 2>/dev/null | head -30
ls -la /dev/mmcblk0p* 2>/dev/null | head -60

sec "block partition table"
cat /proc/partitions

sec "crash dump regions"
grep -iE "mmcoops|wdtlog|snapshot|resume" /proc/cmdline
ls -la /dev/mmcblk0p51 2>/dev/null
ls -la /sys/fs/pstore 2>/dev/null

sec "device tree presence"
ls -d /proc/device-tree 2>/dev/null && echo "DTB PRESENT"
cat /proc/device-tree/model 2>/dev/null; cat /proc/device-tree/compatible 2>/dev/null | tr '\0' ' '
ls /proc/device-tree 2>/dev/null | head -25

sec "writable staging candidates"
df -h /var /var/lib/webosbrew /tmp /media/developer 2>/dev/null
du -sh /var/lib/webosbrew 2>/dev/null
mount | grep -E "webosbrew|developer|cryptofs|squashfs" | head -12

sec "android-relevant kernel caps"
grep -E "binder|ashmem" /proc/devices 2>/dev/null || echo "no binder/ashmem registered"
ls -la /dev/binder* /dev/ashmem 2>/dev/null || echo "no binder/ashmem nodes"

sec "selinux"
getenforce 2>/dev/null || cat /sys/fs/selinux/enforce 2>/dev/null || echo "no selinux interface"

sec "pwn state"
id
grep -cE "applications/|services/|cdp-30|nullfile" /proc/mounts
for p in /proc/[0-9]*/comm; do cat $p; done 2>/dev/null | grep -icE "remotelog|uploadd|voiceinput|voiceconduct|faultmanager|sportsalert|membership|assetmanager"
grep -n "lge.com" /etc/hosts

echo "=== phase0 done ==="
