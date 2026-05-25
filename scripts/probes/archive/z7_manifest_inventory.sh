#!/bin/ash
# K2 Plus Probe #7 - Manifest / Baseline Verification Inventory
# Goal: generate diff-friendly manifests of:
#   - /rom (vendor baseline; readonly squashfs)
#   - /overlay/upper (actual overrides; small != insignificant)
#   - selected /mnt/UDISK areas (persistent configs + installed features)
#
# Output format (tab-delimited):
#   KIND  MODE  UID  GID  SIZE  MTIME_EPOCH  SHA256  LINK_TARGET  PATH
#
# Notes:
# - SHA256 is only computed for "small" regular files (default <= 256 KiB) and if sha256sum exists.
# - We avoid giant/noisy trees (logs, gcodes, timelapse, ai_image) to keep output actionable.

echo "===== K2 PLUS PROBE #5C START (MANIFEST / BASELINE VERIFICATION) ====="
date

SMALL_HASH_MAX_BYTES=262144  # 256 KiB
HASH_CMD=""
STAT_CMD=""

command -v sha256sum >/dev/null 2>&1 && HASH_CMD="sha256sum"
command -v stat >/dev/null 2>&1 && STAT_CMD="stat"

# ---------- helpers ----------
print_kv() { echo "$1: $2"; }

mount_info() {
  # best-effort mount info (works on OpenWrt-ish images)
  # prints: source, mountpoint, fstype, options
  local p="$1"
  local mp src fstype opts
  mp="$(awk -v P="$p" 'BEGIN{best=""} { if (index(P,$2)==1 && length($2)>length(best)) best=$2 } END{print best}' /proc/mounts)"
  if [ -n "$mp" ]; then
    src="$(awk -v M="$mp" '$2==M {print $1; exit}' /proc/mounts)"
    fstype="$(awk -v M="$mp" '$2==M {print $3; exit}' /proc/mounts)"
    opts="$(awk -v M="$mp" '$2==M {print $4; exit}' /proc/mounts)"
  else
    src="n/a"; fstype="n/a"; opts="n/a"; mp="n/a"
  fi
  echo "Mount info: $p"
  echo "  Source:     $src"
  echo "  Mountpoint: $mp"
  echo "  FSType:     $fstype"
  echo "  Options:    $opts"
}

safe_stat_line() {
  # Emits one manifest line for a given path
  # Uses stat if available; falls back to ls parsing if not.
  local p="$1"
  local kind mode uid gid size mtime sha lnk
  sha="-"
  lnk="-"

  if [ -L "$p" ]; then
    kind="L"
    lnk="$(readlink "$p" 2>/dev/null)"
    [ -z "$lnk" ] && lnk="-"
  elif [ -d "$p" ]; then
    kind="D"
  elif [ -f "$p" ]; then
    kind="F"
  else
    kind="O"
  fi

  if [ -n "$STAT_CMD" ]; then
    # mode as octal perms only, uid/gid numeric, size bytes, mtime epoch
    # BusyBox stat generally supports -c
    mode="$(stat -c '%a' "$p" 2>/dev/null)"
    uid="$(stat -c '%u' "$p" 2>/dev/null)"
    gid="$(stat -c '%g' "$p" 2>/dev/null)"
    size="$(stat -c '%s' "$p" 2>/dev/null)"
    mtime="$(stat -c '%Y' "$p" 2>/dev/null)"
  else
    # fallback: limited fidelity
    mode="-"; uid="-"; gid="-"
    size="$(ls -ln "$p" 2>/dev/null | awk '{print $5}')"
    mtime="-"
  fi

  # optional hash for small regular files
  if [ "$kind" = "F" ] && [ -n "$HASH_CMD" ] && [ -n "$size" ] && [ "$size" -le "$SMALL_HASH_MAX_BYTES" ] 2>/dev/null; then
    sha="$($HASH_CMD "$p" 2>/dev/null | awk '{print $1}')"
    [ -z "$sha" ] && sha="-"
  fi

  # tab-delimited (stable for diffs)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$kind" "${mode:--}" "${uid:--}" "${gid:--}" "${size:--}" "${mtime:--}" "$sha" "$lnk" "$p"
}

manifest_tree() {
  # $1 = label, $2 = root path, $3 = find options (e.g. "-xdev")
  local label="$1"
  local root="$2"
  local fopts="$3"

  echo ""
  echo "=== MANIFEST: $label ==="
  echo "Root: $root"
  mount_info "$root"

  if [ ! -e "$root" ]; then
    echo "Missing: $root"
    return 0
  fi

  # header line for easy parsing
  echo "KIND	MODE	UID	GID	SIZE	MTIME_EPOCH	SHA256	LINK_TARGET	PATH"

  # We include dirs, symlinks, and files. Exclude special proc-ish nodes by default.
  # Sort ensures stable ordering across runs.
  #
  # NOTE: assumes paths are sane (no newlines). On this appliance FS, that’s a reasonable assumption.
  find "$root" $fopts \( -type f -o -type d -o -type l \) 2>/dev/null \
    | sort \
    | while read -r p; do
        safe_stat_line "$p"
      done
}

manifest_tree_pruned() {
  # Like manifest_tree, but prunes noisy/heavy directories.
  # $1 label, $2 root, $3 find_opts, remaining args are prune paths relative to root
  local label="$1"
  local root="$2"
  local fopts="$3"
  shift 3

  echo ""
  echo "=== MANIFEST: $label (pruned) ==="
  echo "Root: $root"
  mount_info "$root"

  if [ ! -e "$root" ]; then
    echo "Missing: $root"
    return 0
  fi

  echo "KIND	MODE	UID	GID	SIZE	MTIME_EPOCH	SHA256	LINK_TARGET	PATH"

  # Build prune expression
  # Example: -path "$root/logs" -o -path "$root/gcodes"
  local prune_expr=""
  for rel in "$@"; do
    prune_expr="$prune_expr -path $root/$rel -o"
  done

  if [ -n "$prune_expr" ]; then
    # strip trailing -o
    prune_expr="${prune_expr% -o}"
    # shellcheck disable=SC2086
    find "$root" $fopts \( $prune_expr \) -prune -o \( -type f -o -type d -o -type l \) -print 2>/dev/null \
      | sort \
      | while read -r p; do
          safe_stat_line "$p"
        done
  else
    manifest_tree "$label" "$root" "$fopts"
  fi
}

# ---------- context / quick discovery ----------
echo ""
echo "=== CONTEXT: key symlinks (sanity) ==="
ls -la /opt 2>/dev/null || true
ls -la /usr/share/fluidd 2>/dev/null || true
ls -la /etc/init.d/moonraker 2>/dev/null || true
ls -la /etc/init.d/klipper 2>/dev/null || true

echo ""
echo "=== CONTEXT: /rom submounts (from /proc/mounts) ==="
awk '$2 ~ "^/rom/" {print $2 " (" $3 ")"}' /proc/mounts | sort

# ---------- manifests ----------
# 1) Vendor baseline
manifest_tree "ROM baseline (/rom, xdev)" "/rom" "-xdev"

# 2) Overlay overrides (critical even if small)
manifest_tree "Overlay overrides (/overlay/upper)" "/overlay/upper" ""

# 3) Persistent verification targets under UDISK
# We keep this targeted and pruned to avoid “logs-as-noise”.
manifest_tree_pruned "UDISK printer_data (configs + state)" "/mnt/UDISK/printer_data" "-xdev" \
  "logs" "gcodes"

manifest_tree_pruned "UDISK creality userdata (configs + policies)" "/mnt/UDISK/creality/userdata" "-xdev" \
  "log" "delay_image" "history"

manifest_tree "UDISK root (includes installed UI bits)" "/mnt/UDISK/root" "-xdev"

# Optional: k2-improvements specifically (this is your “reapply + compare” anchor)
if [ -d /mnt/UDISK/root/k2-improvements ]; then
  manifest_tree "k2-improvements (/mnt/UDISK/root/k2-improvements)" "/mnt/UDISK/root/k2-improvements" "-xdev"
fi

# Optional: Entware (opt) – mostly for verification that tools exist / versions changed
if [ -d /mnt/UDISK/opt ]; then
  manifest_tree "Entware (/mnt/UDISK/opt, xdev)" "/mnt/UDISK/opt" "-xdev"
fi

echo ""
echo "===== K2 PLUS PROBE #7 END ====="