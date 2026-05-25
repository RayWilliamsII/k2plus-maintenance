#!/bin/sh
set -eu

echo "===== K2 PLUS PROBE #4 START (VENDOR WEB SERVER CONFIG) ====="
date

echo
echo "=== /var/www/html inventory ==="
ls -la /var/www 2>/dev/null || true
ls -la /var/www/html 2>/dev/null || true
find /var/www/html -maxdepth 3 -type f 2>/dev/null | head -n 200 || true

echo
echo "=== Locate httpd.conf / web-server config files (limited) ==="
for base in /etc /mnt/UDISK /usr/share /var; do
  [ -d "$base" ] || continue
  echo "--- searching under $base ---"
  find "$base" -maxdepth 6 -type f \( -iname "httpd.conf" -o -iname "*web*.conf" -o -iname "*server*.conf" -o -iname "log_config.json" \) 2>/dev/null \
    | head -n 200 || true
done

echo
echo "=== Show key vendor configs (if present) ==="
for f in \
  /mnt/UDISK/creality/userdata/config/system_config.json \
  /mnt/UDISK/creality/userdata/log/log_config.json \
  /etc/sysConfig/system_config.json \
  /etc/sysConfig/log_config.json \
  /etc/sysConfig/httpd.conf \
  /etc/httpd.conf \
  /var/www/httpd.conf \
  /var/www/html/httpd.conf
do
  if [ -f "$f" ]; then
    echo "--- $f (first 200 lines) ---"
    sed -n '1,200p' "$f"
    echo
  fi
done

echo
echo "=== system_config.json: extract a few non-secret fields (jq if available) ==="
CONFIG=/mnt/UDISK/creality/userdata/config/system_config.json
if [ -f "$CONFIG" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq '{user_info: {deploy_setting: .user_info.deploy_setting, language: .user_info.language}, network: (.network? // null)}' "$CONFIG" 2>/dev/null || true
  else
    echo "jq not available"
  fi
fi

echo
echo "=== k2-improvements git status (force /opt/bin in PATH) ==="
export PATH="/opt/bin:/opt/sbin:$PATH"
if command -v git >/dev/null 2>&1 && [ -d /mnt/UDISK/root/k2-improvements/.git ]; then
  cd /mnt/UDISK/root/k2-improvements
  echo "HEAD: $(git rev-parse HEAD 2>/dev/null || true)"
  git status -sb 2>/dev/null || true
fi

echo
echo "===== K2 PLUS PROBE #4 END ====="