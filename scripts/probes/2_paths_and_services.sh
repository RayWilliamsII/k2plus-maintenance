#!/bin/sh
set -eu

echo "===== K2 PLUS PROBE #2 START (PATHS/SERVICES) ====="
date

echo
echo "=== KEY PATHS (sanity) ==="
echo "PWD: $(pwd)"
echo "/opt -> $(readlink /opt 2>/dev/null || echo 'n/a')"
echo "/etc/init.d/moonraker -> $(readlink /etc/init.d/moonraker 2>/dev/null || echo 'n/a')"
echo "/etc/init.d/klipper -> $(readlink /etc/init.d/klipper 2>/dev/null || echo 'n/a')"

echo
echo "=== RUNNING PROCESSES (focused) ==="
ps w | grep -E "[m]oonraker|[k]lippy|[k]lipper_mcu|[n]ginx|[w]eb-server|[w]ebrtc|[d]ropbear" || true

echo
echo "=== LISTENING PORTS (focused) ==="
netstat -lntp 2>/dev/null | grep -E "(:22|:80|:4408|:7125|:8000|:9999)\b" || true

echo
echo "=== NGINX CONFIG (files + full expanded) ==="
echo "--- ls -la /etc/nginx ---"
ls -la /etc/nginx 2>/dev/null || true

echo
echo "--- nginx -t (config test) ---"
nginx -t 2>&1 || true

echo
echo "--- nginx -T (full config dump) ---"
# This can be verbose; that's OK — we want the full include-expanded config.
nginx -T 2>&1 || true

echo
echo "=== NGINX: PATH/UPSTREAM HINTS (grep) ==="
# Pull likely web roots, aliases, upstreams, and proxied endpoints out of /etc/nginx
for f in /etc/nginx/nginx.conf /etc/nginx/*.conf /etc/nginx/conf.d/*.conf /etc/nginx/*/*.conf; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  grep -nE "root |alias |try_files|location |proxy_pass|upstream |listen |server_name|include " "$f" 2>/dev/null || true
done

echo
echo "=== WEB ROOT DISCOVERY (common locations) ==="
for d in /www /www/* /usr/share /usr/share/* /mnt/UDISK/www /mnt/UDISK/www/* /mnt/UDISK/opt /mnt/UDISK/opt/*; do
  [ -d "$d" ] || continue
  echo "--- ls -la $d ---"
  ls -la "$d" 2>/dev/null | head -n 80 || true
done

echo
echo "=== FLUIDD/Mainsail UI DISCOVERY (find, limited depth) ==="
for base in / /usr/share /www /mnt/UDISK /mnt/UDISK/opt /opt; do
  [ -d "$base" ] || continue
  echo "--- searching under $base (maxdepth 6) ---"
  find "$base" -maxdepth 6 -type d \( -iname "*fluidd*" -o -iname "*mainsail*" \) 2>/dev/null | head -n 200 || true
done

echo
echo "=== PRINTER_DATA INVENTORY (configs/state) ==="
for d in /mnt/UDISK/printer_data /mnt/UDISK/printer_data/config /mnt/UDISK/printer_data/logs /mnt/UDISK/printer_data/database; do
  [ -d "$d" ] || continue
  echo "--- $d ---"
  ls -la "$d" 2>/dev/null | head -n 200 || true
done

echo
echo "=== K2 IMPROVEMENTS FOOTPRINT (if present) ==="
if [ -d /mnt/UDISK/root/k2-improvements ]; then
  echo "--- /mnt/UDISK/root/k2-improvements (top) ---"
  ls -la /mnt/UDISK/root/k2-improvements | head -n 200 || true

  echo
  echo "--- features directory ---"
  ls -la /mnt/UDISK/root/k2-improvements/features 2>/dev/null | head -n 200 || true

  echo
  echo "--- init script target (moonraker.init) ---"
  ls -la /mnt/UDISK/root/k2-improvements/features/moonraker 2>/dev/null || true
  sed -n '1,200p' /mnt/UDISK/root/k2-improvements/features/moonraker/moonraker.init 2>/dev/null || true
else
  echo "Not found: /mnt/UDISK/root/k2-improvements"
fi

echo
echo "=== INIT SCRIPT CONTENTS (key ones) ==="
for f in /etc/init.d/klipper /etc/init.d/klipper_mcu /etc/init.d/moonraker /etc/init.d/nginx; do
  [ -e "$f" ] || continue
  echo "--- $f (first 220 lines) ---"
  sed -n '1,220p' "$f" 2>/dev/null || true
  echo
done

echo
echo "=== SYMLINK TARGETS (high-value) ==="
for p in /etc/init.d/moonraker /etc/init.d/klipper /etc/init.d/klipper_mcu /etc/nginx/uci.conf /opt; do
  [ -e "$p" ] || continue
  echo "$p -> $(readlink -f "$p" 2>/dev/null || readlink "$p" 2>/dev/null || echo 'n/a')"
done

echo
echo "===== K2 PLUS PROBE #2 END ====="