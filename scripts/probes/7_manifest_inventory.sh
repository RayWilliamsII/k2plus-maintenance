#!/bin/ash
# K2 Plus Probe #7 - Manifest / Baseline Verification Inventory (manifest-only)
# Output format (tab-delimited):
#   KIND  MODE  UID  GID  SIZE  MTIME_EPOCH  SHA256  LINK_TARGET  PATH
#
# KIND: D=dir, F=file, L=symlink, O=other
# SHA256 computed only for small regular files (<= 256 KiB) if sha256sum exists.

echo "===== K2 PLUS PROBE #7 START (MANIFEST / BASELINE VERIFICATION) ====="
date

SMALL_HASH_MAX_BYTES=262144  # 256 KiB
HASH_CMD=""
STAT_CMD=""

command -v sha256sum >/dev/null 2>&1 && HASH_CMD="sha256sum"
command -v stat >/dev/null 2>&1 && STAT_CMD="stat"

mount_info_one_line() {
  # prints: source|mountpoint|fstype|options (best match mountpoint)
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
  printf "%s|%s|%s|%s" "$src" "$mp" "$fstype" "$opts"
}

safe_stat_line() {
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
    mode="$(stat -c '%a' "$p" 2>/dev/null)"
    uid="$(stat -c '%u' "$p" 2>/dev/null)"
    gid="$(stat -c '%g' "$p" 2>/dev/null)"
    size="$(stat -c '%s' "$p" 2>/dev/null)"
    mtime="$(stat -c '%Y' "$p" 2>/dev/null)"
  else
    mode="-"; uid="-"; gid="-"
    size="$(ls -ln "$p" 2>/dev/null | awk '{print $5}')"
    mtime="-"
  fi

  if [ "$kind" = "F" ] && [ -n "$HASH_CMD" ] && [ -n "$size" ] && [ "$size" -le "$SMALL_HASH_MAX_BYTES" ] 2>/dev/null; then
    sha="$($HASH_CMD "$p" 2>/dev/null | awk '{print $1}')"
    [ -z "$sha" ] && sha="-"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$kind" "${mode:--}" "${uid:--}" "${gid:--}" "${size:--}" "${mtime:--}" "$sha" "$lnk" "$p"
}

manifest_tree() {
  # $1 label, $2 root, $3 find opts (e.g. -xdev)
  local label="$1"
  local root="$2"
  local fopts="$3"

  echo ""
  echo "=== MANIFEST: $label ==="
  echo "ROOT: $root"
  echo "MOUNT: $(mount_info_one_line "$root")"
  echo "KIND	MODE	UID	GID	SIZE	MTIME_EPOCH	SHA256	LINK_TARGET	PATH"

  [ -e "$root" ] || { echo "# Missing root: $root"; return 0; }

  find "$root" $fopts \( -type f -o -type d -o -type l \) 2>/dev/null \
    | sort \
    | while read -r p; do
        safe_stat_line "$p"
      done
}

manifest_tree_pruned() {
  # $1 label, $2 root, $3 find opts, then prune relpaths under root
  local label="$1"
  local root="$2"
  local fopts="$3"
  shift 3

  echo ""
  echo "=== MANIFEST: $label (pruned) ==="
  echo "ROOT: $root"
  echo "MOUNT: $(mount_info_one_line "$root")"
  echo "KIND	MODE	UID	GID	SIZE	MTIME_EPOCH	SHA256	LINK_TARGET	PATH"

  [ -e "$root" ] || { echo "# Missing root: $root"; return 0; }

  local prune_expr=""
  for rel in "$@"; do
    prune_expr="$prune_expr -path $root/$rel -o"
  done

  if [ -n "$prune_expr" ]; then
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

# 1) Vendor baseline
manifest_tree "ROM baseline (/rom, xdev)" "/rom" "-xdev"

# 2) Overlay overrides (small but can be critical)
manifest_tree "Overlay overrides (/overlay/upper)" "/overlay/upper" ""

# 3) Persistent verification targets under UDISK (pruned for signal)
manifest_tree_pruned "UDISK printer_data" "/mnt/UDISK/printer_data" "-xdev" "logs" "gcodes"
manifest_tree_pruned "UDISK creality userdata" "/mnt/UDISK/creality/userdata" "-xdev" "log" "delay_image" "history"

# 4) Installed bits / scripts (typically what you reapply then verify)
manifest_tree "UDISK root" "/mnt/UDISK/root" "-xdev"

if [ -d /mnt/UDISK/root/k2-improvements ]; then
  manifest_tree "k2-improvements" "/mnt/UDISK/root/k2-improvements" "-xdev"
fi

if [ -d /mnt/UDISK/opt ]; then
  manifest_tree "Entware (/mnt/UDISK/opt, xdev)" "/mnt/UDISK/opt" "-xdev"
fi

echo ""
echo "===== K2 PLUS PROBE #7 END ====="