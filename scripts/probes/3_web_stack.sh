#!/bin/sh
set -eu

echo "===== K2 PLUS PROBE #3 START (WEB STACK / SERVICES) ====="
date

echo
echo "=== web-server binary + strings ==="
command -v web-server 2>/dev/null || true
ls -la /usr/bin/web-server 2>/dev/null || true
# lightweight hints (busybox strings may exist; ignore if not)
strings /usr/bin/web-server 2>/dev/null | grep -E -i "conf|config|www|html|root|listen|port|nginx|fluidd|mainsail|moonraker" | head -n 200 || true

echo
echo "=== Init scripts: likely web/cam ==="
ls -la /etc/init.d 2>/dev/null | grep -E "web|cam|mjpg|stream|rtsp|webrtc|nginx|dropbear" || true

echo
echo "=== /etc/init.d/webrtc (if present) ==="
[ -f /etc/init.d/webrtc ] && { sed -n '1,240p' /etc/init.d/webrtc; echo; } || echo "No /etc/init.d/webrtc"

echo
echo "=== /etc/init.d/app and device_manager (often starts vendor web bits) ==="
[ -f /etc/init.d/app ] && { sed -n '1,260p' /etc/init.d/app; echo; } || echo "No /etc/init.d/app"
[ -f /etc/init.d/device_manager ] && { sed -n '1,260p' /etc/init.d/device_manager; echo; } || echo "No /etc/init.d/device_manager"

echo
echo "=== Running cmdlines (web-server/webrtc) ==="
ps w | grep -E "[w]eb-server|[w]ebrtc" || true

echo
echo "=== Find web-server related configs (limited) ==="
for base in /etc /usr/share /mnt/UDISK; do
  [ -d "$base" ] || continue
  echo "--- searching under $base ---"
  find "$base" -maxdepth 5 -type f \( -iname "*web-server*" -o -iname "*webserver*" -o -iname "*webrtc*" -o -iname "*mjpg*" -o -iname "*stream*" -o -iname "*.json" -o -iname "*.conf" \) 2>/dev/null \
    | head -n 250 || true
done

echo
echo "=== Dropbear config (auth + keys) ==="
dropbear -V 2>/dev/null || true
ps w | grep -E "[d]ropbear" || true
ls -la /etc/dropbear 2>/dev/null || true
[ -f /etc/dropbear/authorized_keys ] && { echo "--- /etc/dropbear/authorized_keys (tail) ---"; tail -n 5 /etc/dropbear/authorized_keys; } || true
ls -la /root/.ssh 2>/dev/null || true
[ -f /root/.ssh/authorized_keys ] && { echo "--- /root/.ssh/authorized_keys (tail) ---"; tail -n 5 /root/.ssh/authorized_keys; } || true

echo
echo "=== Quick backup classification hints ==="
echo "--- printer_data/config (top) ---"
ls -la /mnt/UDISK/printer_data/config 2>/dev/null | head -n 80 || true
echo "--- printer_data/database ---"
ls -la /mnt/UDISK/printer_data/database 2>/dev/null | head -n 80 || true
echo "--- k2-improvements git status (if git exists) ---"
if command -v git >/dev/null 2>&1 && [ -d /mnt/UDISK/root/k2-improvements/.git ]; then
  cd /mnt/UDISK/root/k2-improvements
  git rev-parse HEAD 2>/dev/null || true
  git status -sb 2>/dev/null || true
fi

echo
echo "===== K2 PLUS PROBE #3 END ====="