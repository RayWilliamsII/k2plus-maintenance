#!/usr/bin/env bash
set -euo pipefail

K2_HOST="${K2_HOST:-k2plus.local}"
K2_USER="${K2_USER:-root}"
BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

TARGET_MODE="${1:-}"
if [[ "$TARGET_MODE" != "lkg" && "$TARGET_MODE" != "current" ]]; then
  echo "Usage: $0 {lkg|current}" >&2
  exit 2
fi

SNAP_LKG="${BASE_DIR}/snapshot_lkg"
SNAP_CUR="${BASE_DIR}/snapshot_current"
DEST_DIR="$([[ "$TARGET_MODE" == "lkg" ]] && echo "$SNAP_LKG" || echo "$SNAP_CUR")"

ensure_safe_dest() {
  local d="$1"
  local real real_lkg real_cur
  real="$(readlink -f "$d" 2>/dev/null || true)"
  real_lkg="$(readlink -f "$SNAP_LKG" 2>/dev/null || true)"
  real_cur="$(readlink -f "$SNAP_CUR" 2>/dev/null || true)"

  if [[ -z "$real" || ( "$real" != "$real_lkg" && "$real" != "$real_cur" ) ]]; then
    echo "Refusing: destination path is not an approved snapshot directory:" >&2
    echo "  DEST: ${d} (resolved: ${real})" >&2
    echo "  Allowed: ${SNAP_LKG} (resolved: ${real_lkg})" >&2
    echo "           ${SNAP_CUR} (resolved: ${real_cur})" >&2
    exit 3
  fi
}

# Pull “as accessed on the system”:
# -L dereference symlinks and copy file contents (not link objects)
# -t preserve mtime (you asked for this)
# no perms/owner/group/acls/xattrs
RSYNC_FLAGS=(
  "-rLt"
  "--no-perms"
  "--no-owner"
  "--no-group"
)

INCLUDE_PATHS=(
  "/mnt/UDISK/printer_data"
  "/mnt/UDISK/root"
  "/mnt/UDISK/creality"
  "/overlay/upper"
  "/mnt/UDISK/opt"
  "/rom"
)

RSYNC_EXCLUDES=(
  "--exclude=/mnt/UDISK/printer_data/logs/***"
  "--exclude=/mnt/UDISK/creality/userdata/log/***"
  "--exclude=/mnt/UDISK/creality/userdata/delay_image/***"
  "--exclude=/mnt/UDISK/timelapse/***"
  "--exclude=/mnt/UDISK/ai_image/***"
  "--exclude=/mnt/UDISK/layers_image/***"
  "--exclude=/mnt/UDISK/tmp/***"
  "--exclude=/mnt/UDISK/opt/tmp/***"
)

SSH_OPTS=(
  "-o" "BatchMode=yes"
  "-o" "IdentitiesOnly=yes"
)

command -v rsync >/dev/null 2>&1 || { echo "rsync is required on the local machine." >&2; exit 4; }

echo "== Connectivity check =="
ssh "${SSH_OPTS[@]}" "${K2_USER}@${K2_HOST}" "echo ok" >/dev/null

mkdir -p "$DEST_DIR"
ensure_safe_dest "$DEST_DIR"

if [[ "$TARGET_MODE" == "current" ]]; then
  echo "== Wiping snapshot_current =="
  find "$DEST_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi

echo "== Pulling snapshot to: $DEST_DIR =="
echo "Host: ${K2_USER}@${K2_HOST}"
echo

for src in "${INCLUDE_PATHS[@]}"; do
  rel="${src#/}"
  out="${DEST_DIR}/${rel}"
  mkdir -p "$out"

  echo "-- rsync: $src -> $out"
  rsync "${RSYNC_FLAGS[@]}" --info=stats2,progress2 \
    "${RSYNC_EXCLUDES[@]}" \
    -e "ssh ${SSH_OPTS[*]}" \
    "${K2_USER}@${K2_HOST}:${src}/" \
    "${out}/"
  echo
done

echo "== Done =="
echo "Snapshot written to: $DEST_DIR"