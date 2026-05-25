#!/bin/sh
# K2 PLUS PROBE #6 - PERSISTENT DIRECTORY INVENTORY (UDISK + OVERLAY)
# Goal: Read-only, depth-limited inventory of key persistent paths.
# Output: sizes + file/dir counts for immediate children, plus totals.
# Notes:
# - No “space management” recommendations; this is discovery only.
# - BusyBox-friendly; avoids non-portable options.

set -eu

PROBE_NAME="K2 PLUS PROBE #6"
PROBE_DESC="PERSISTENT DIRECTORY INVENTORY (UDISK + OVERLAY)"

echo "===== ${PROBE_NAME} START (${PROBE_DESC}) ====="
date

# ---------- helpers ----------
have_cmd() { command -v "$1" >/dev/null 2>&1; }

human_kib() {
  # Input: KiB integer on stdin -> "12345 KB (12 MiB)"
  # BusyBox awk used for simple MiB rendering.
  awk '{
    kb=$1;
    mib=kb/1024.0;
    printf "%d KB (%.0f MiB)\n", kb, mib
  }'
}

mount_info_for_path() {
  p="$1"
  # Try to show mountpoint/source/fstype/options for a path.
  # BusyBox may lack findmnt; use /proc/mounts + longest-prefix match.
  echo "Mount info: ${p}"
  awk -v target="$p" '
    BEGIN { bestlen=0; bestline="" }
    {
      mp=$2; src=$1; fs=$3; opts=$4;
      # Normalize: ensure mountpoint is prefix of target
      if (index(target, mp) == 1) {
        l=length(mp);
        # require boundary: either exact or next char is "/"
        if (target == mp || substr(target, l+1, 1) == "/") {
          if (l > bestlen) {
            bestlen=l;
            bestline=src " " mp " " fs " " opts;
          }
        }
      }
    }
    END {
      if (bestline == "") {
        print "  Mountpoint: n/a";
        print "  Source:     n/a";
        print "  FSType:     n/a";
        print "  Options:    n/a";
      } else {
        split(bestline, a, " ");
        print "  Source:     " a[1];
        print "  Mountpoint: " a[2];
        print "  FSType:     " a[3];
        print "  Options:    " a[4];
      }
    }
  ' /proc/mounts
}

df_for_path() {
  p="$1"
  echo "--- df -h ${p} ---"
  df -h "$p" 2>/dev/null || true
}

# BusyBox du may not support -x. We constrain crossing FS by enumerating mountpoint children
# separately (for /mnt/UDISK and /overlay they’re real mountpoints so du stays local).
dir_size_kb() {
  # Returns KiB integer for a directory path
  d="$1"
  # BusyBox du -sk prints "KB path"
  du -sk "$d" 2>/dev/null | awk '{print $1}'
}

count_files_dirs() {
  # counts within dir; uses find without crossing FS by staying on same mountpoint
  d="$1"
  # Some builds have find; if not, return n/a
  if have_cmd find; then
    files=$(find "$d" -type f 2>/dev/null | wc -l | awk '{print $1}')
    dirs=$(find "$d" -type d 2>/dev/null | wc -l | awk '{print $1}')
    echo "Files: ${files}"
    echo "Dirs:  ${dirs}"
  else
    echo "Files: n/a (find not available)"
    echo "Dirs:  n/a (find not available)"
  fi
}

safe_ls_children() {
  base="$1"
  # Emit immediate children directories (not files) with absolute paths.
  # Avoid errors if empty/missing.
  if [ -d "$base" ]; then
    # Use ls -1A to list entries; then test directories.
    ls -1A "$base" 2>/dev/null | while IFS= read -r e; do
      p="${base%/}/$e"
      [ -d "$p" ] && echo "$p"
    done
  fi
}

print_dir_row() {
  d="$1"
  kb="$(dir_size_kb "$d" || echo 0)"
  printf "%10s  %s\n" "${kb}KB" "$d"
}

inventory_depth1() {
  base="$1"
  title="$2"

  echo
  echo "=== ${title} ==="
  echo "Path: ${base}"

  if [ ! -e "$base" ]; then
    echo "Status: missing"
    return 0
  fi
  if [ ! -d "$base" ]; then
    echo "Status: exists but is not a directory"
    return 0
  fi

  mount_info_for_path "$base"
  df_for_path "$base"

  echo "--- base du summary ---"
  base_kb="$(dir_size_kb "$base" || echo 0)"
  echo "$base_kb" | human_kib

  echo "--- base counts (files/dirs) ---"
  count_files_dirs "$base"

  echo "--- immediate children (dirs only): size summary (KB) ---"
  # Collect children rows then sort numerically by KB desc if sort exists.
  tmp="/tmp/probe5b.$$"
  : > "$tmp"
  safe_ls_children "$base" | while IFS= read -r child; do
    kb="$(dir_size_kb "$child" || echo 0)"
    printf "%s\t%s\n" "$kb" "$child" >> "$tmp"
  done

  if [ ! -s "$tmp" ]; then
    echo "(no child directories found)"
    rm -f "$tmp"
    return 0
  fi

  if have_cmd sort; then
    # Sort numeric desc by first field
    sort -nr -k1,1 "$tmp" | awk -F'\t' '{printf "%10sKB  %s\n", $1, $2}'
  else
    awk -F'\t' '{printf "%10sKB  %s\n", $1, $2}' "$tmp"
  fi

  rm -f "$tmp"
}

# ---------- main ----------
# Targets: persistent layers only
inventory_depth1 "/mnt/UDISK" "PERSISTENT: /mnt/UDISK (primary data)"
inventory_depth1 "/overlay"   "PERSISTENT: /overlay (overlay upper/work filesystem)"

# Optional: common subpaths we already care about (printed if present)
echo
echo "=== KEY SUBPATHS (if present) ==="
for p in \
  "/mnt/UDISK/printer_data" \
  "/mnt/UDISK/root" \
  "/mnt/UDISK/root/k2-improvements" \
  "/mnt/UDISK/creality" \
  "/mnt/UDISK/creality/userdata" \
  "/mnt/UDISK/opt" \
  "/overlay/upper" \
  "/overlay/work"
do
  if [ -d "$p" ]; then
    kb="$(dir_size_kb "$p" || echo 0)"
    echo "--- ${p} ---"
    echo "$kb" | human_kib
    count_files_dirs "$p"
  fi
done

echo
echo "===== ${PROBE_NAME} END ====="