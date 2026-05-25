#!/bin/sh
# K2 Plus capability + layout probe
# Read-only, BusyBox-safe

set -u

echo "===== K2 PLUS PROBE START ====="
date
echo

echo "=== SYSTEM IDENTIFICATION ==="
uname -a 2>/dev/null || true
echo
[ -f /etc/os-release ] && cat /etc/os-release
[ -f /etc/openwrt_release ] && cat /etc/openwrt_release
echo

echo "=== BUSYBOX ==="
#busybox 2>/dev/null | head -n 2 || echo "busybox not found"
md5sum --help 2>&1 | head -1
echo

echo "=== TOOL AVAILABILITY ==="
for c in sh ash bash busybox tar gzip xz unzip zip rsync scp sftp wget curl \
         python3 python pip3 pip opkg git \
         find sed awk grep cut xargs \
         md5sum sha256sum \
         ps top free df mount lsblk \
         netstat ss lsof; do
  if command -v "$c" >/dev/null 2>&1; then
    echo "OK  $c -> $(command -v "$c")"
  else
    echo "NO  $c"
  fi
done
echo

echo "=== FILESYSTEM / MOUNTS ==="
mount || true
echo
echo "--- /proc/mounts ---"
cat /proc/mounts || true
echo
df -hT || true
echo

echo "=== OVERLAY / PERSISTENCE CLUES ==="
grep -iE "overlay|upperdir|workdir|squashfs|ubifs|jffs2" /proc/mounts || echo "No overlay clues found"
echo

echo "=== TOP-LEVEL DIRECTORY SNAPSHOT ==="
for d in /etc /usr /opt /root /home /mnt /www /var; do
  if [ -e "$d" ]; then
    echo "--- $d ---"
    ls -la "$d" | head -n 80
    echo
  fi
done

echo "=== SERVICE / PROCESS DISCOVERY ==="
ps w 2>/dev/null | grep -iE "klipper|moonraker|fluidd|mainsail|nginx|uhttpd|python|node" | grep -v grep || true
echo

echo "=== LISTENING PORTS ==="
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null || echo "No port tool available") | head -n 200
echo

echo "=== INIT / SERVICE FILES ==="
[ -d /etc/init.d ] && ls -la /etc/init.d
echo
grep -RinE "klipper|moonraker|fluidd|nginx|uhttpd|python|node" /etc/init.d 2>/dev/null | head -n 200 || true
echo

echo "=== SYMLINK DISCOVERY (LIMITED DEPTH) ==="
find /etc /usr /opt /root /www -maxdepth 3 -type l 2>/dev/null | head -n 200
echo

echo "===== K2 PLUS PROBE END ====="