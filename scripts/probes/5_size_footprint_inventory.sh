#!/bin/sh
# Probe #5 - Size / Footprint Inventory (K2 Plus / OpenWrt BusyBox friendly)

set -eu

echo "===== K2 PLUS PROBE #5 START (SIZE / FOOTPRINT INVENTORY) ====="
date
echo

# -------- helpers --------

# hr_kb: format KB into friendly units (KiB/MiB/GiB)
hr_kb() {
  kb="${1:-0}"
  # Use integer math only (busybox sh compatible)
  if [ "$kb" -ge 1048576 ] 2>/dev/null; then
    gib=$((kb / 1048576))
    echo "${gib} GiB"
  elif [ "$kb" -ge 1024 ] 2>/dev/null; then
    mib=$((kb / 1024))
    echo "${mib} MiB"
  else
    echo "${kb} KiB"
  fi
}

# du_kb: return total KB for a path (best effort)
du_kb() {
  p="$1"
  # busybox du output: "<kb>  <path>"
  du -sk "$p" 2>/dev/null | awk '{print $1}' | tail -n 1
}

# resolve_path: resolve symlink if possible (important for /opt)
resolve_path() {
  p="$1"
  rp="$p"

  if [ -L "$p" ]; then
    # Prefer readlink -f when present
    if readlink -f "$p" >/dev/null 2>&1; then
      rp="$(readlink -f "$p" 2>/dev/null || echo "$p")"
    else
      link="$(readlink "$p" 2>/dev/null || true)"
      if [ -n "$link" ]; then
        # If the link is relative, anchor it to the dirname of the symlink
        case "$link" in
          /*) rp="$link" ;;
          *)
            d="$(dirname "$p")"
            rp="$d/$link"
            ;;
        esac
      fi
    fi
  fi

  echo "$rp"
}

# mount_for_path: find the most-specific mountpoint that contains a path
# outputs: mountpoint|source|fstype|options  (or n/a if unknown)
mount_for_path() {
  p="$1"
  # Normalize double slashes etc is overkill; just do prefix matching.
  awk -v P="$p" '
    BEGIN { best_len = -1; best_mp=""; best_src=""; best_fs=""; best_opts="" }
    {
      src=$1; mp=$2; fs=$3; opts=$4;
      # P is inside mountpoint if mountpoint is "/" or prefix + boundary
      if (mp == "/") {
        ok = 1
      } else {
        # prefix match
        ok = (index(P, mp) == 1)
        # boundary check (exact match or next char is "/")
        if (ok && length(P) > length(mp)) {
          c = substr(P, length(mp)+1, 1)
          if (c != "/") ok = 0
        }
      }
      if (ok) {
        l = length(mp)
        if (l > best_len) {
          best_len = l
          best_mp = mp
          best_src = src
          best_fs = fs
          best_opts = opts
        }
      }
    }
    END {
      if (best_len >= 0) {
        printf "%s|%s|%s|%s\n", best_mp, best_src, best_fs, best_opts
      } else {
        print "n/a|n/a|n/a|n/a"
      }
    }
  ' /proc/mounts 2>/dev/null
}

# count_items: count files/dirs under a path, prefer -xdev (same filesystem)
# outputs: "<files> <dirs> <mode>"
count_items() {
  p="$1"

  # Try xdev first (busybox find usually supports it)
  if find "$p" -xdev -type f -print >/dev/null 2>&1; then
    files="$(find "$p" -xdev -type f -print 2>/dev/null | wc -l | awk '{print $1}')"
    dirs="$(find "$p" -xdev -type d -print 2>/dev/null | wc -l | awk '{print $1}')"
    echo "${files:-0} ${dirs:-0} xdev"
    return
  fi

  # Fallback without -xdev
  files="$(find "$p" -type f -print 2>/dev/null | wc -l | awk '{print $1}')"
  dirs="$(find "$p" -type d -print 2>/dev/null | wc -l | awk '{print $1}')"
  echo "${files:-0} ${dirs:-0} no-xdev"
}

# section_for_path: emit the standard block for a given path
section_for_path() {
  label="$1"
  p="$2"

  rp="$(resolve_path "$p")"

  echo "=== PATH: $label ==="
  mi="$(mount_for_path "$rp")"
  mp="$(echo "$mi" | cut -d'|' -f1)"
  src="$(echo "$mi" | cut -d'|' -f2)"
  fs="$(echo "$mi" | cut -d'|' -f3)"
  opts="$(echo "$mi" | cut -d'|' -f4)"

  echo "Mountpoint: $mp"
  echo "Source:     $src"
  echo "FSType:     $fs"
  echo "Options:    $opts"
  if [ "$rp" != "$p" ]; then
    echo "Resolved path: $rp"
  fi

  echo "--- df -h $p ---"
  df -h "$p" 2>/dev/null || df -h "$rp" 2>/dev/null || echo "df failed for $p"

  echo "--- du summary ---"
  if [ -e "$rp" ]; then
    total_kb="$(du_kb "$rp")"
    total_kb="${total_kb:-0}"
    echo "Total: ${total_kb} KB ($(hr_kb "$total_kb"))"
  else
    echo "Total: n/a (path not found)"
  fi

  echo "--- counts (find mode: xdev) ---"
  if [ -e "$rp" ]; then
    set -- $(count_items "$rp")
    files="$1"; dirs="$2"; mode="$3"
    echo "Files: ${files:-0}"
    echo "Dirs:  ${dirs:-0}"
    if [ "$mode" != "xdev" ]; then
      echo "Note:  find -xdev not supported; counts may cross filesystems"
    fi
  else
    echo "Files: n/a"
    echo "Dirs:  n/a"
  fi

  echo
}

# -------- report --------

echo "=== /opt resolution ==="
if [ -L /opt ]; then
  echo "/opt is a symlink:"
  ls -l /opt 2>/dev/null || true
else
  echo "/opt is not a symlink"
fi
opt_resolved="$(resolve_path /opt)"
echo "Resolved (/opt): $opt_resolved"
echo

# Standard inventory paths
section_for_path "/rom" "/rom"
section_for_path "/usr" "/usr"
section_for_path "/bin" "/bin"
section_for_path "/etc" "/etc"
section_for_path "/overlay" "/overlay"
section_for_path "/mnt/UDISK" "/mnt/UDISK"
section_for_path "/opt" "/opt"

# -------- /rom breakdown (exclude submounts like /rom/dev) --------

echo "=== /rom top-level breakdown (exclude submounts like /rom/dev) ==="
echo "--- submounts under /rom (from /proc/mounts) ---"
submounts="$(awk '$2 ~ "^/rom/" {print $2}' /proc/mounts 2>/dev/null | sort || true)"
if [ -n "$submounts" ]; then
  echo "$submounts"
else
  echo "(none)"
fi

is_submount() {
  cand="$1"
  echo "$submounts" | grep -qx "$cand"
}

# List direct children of /rom (depth 1)
for entry in /rom/*; do
  [ -e "$entry" ] || continue

  if is_submount "$entry"; then
    echo "SKIP (mount): $entry"
    continue
  fi

  kb="$(du -sk "$entry" 2>/dev/null | awk '{print $1}' | tail -n 1)"
  kb="${kb:-0}"
  echo "${kb} KB  $entry"
done

echo
echo "===== K2 PLUS PROBE #5 END ====="