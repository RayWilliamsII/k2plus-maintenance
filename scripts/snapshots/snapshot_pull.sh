#!/usr/bin/env bash
set -euo pipefail

K2_HOST="${K2_HOST:-k2plus.local}"
K2_USER="${K2_USER:-root}"
BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

MODE="${1:-}"
if [[ "$MODE" != "lkg" && "$MODE" != "current" ]]; then
  echo "Usage: $0 {lkg|current}" >&2
  exit 2
fi

SNAP_LKG="$BASE_DIR/snapshot_lkg"
SNAP_CUR="$BASE_DIR/snapshot_current"

if [[ "$MODE" == "lkg" ]]; then
  DEST_DIR="$SNAP_LKG"
else
  DEST_DIR="$SNAP_CUR"
fi

SSH_OPTS=(
  -o BatchMode=yes
  -o IdentitiesOnly=yes
)

RSYNC_FLAGS=(
  -rLt
  --no-perms
  --no-owner
  --no-group
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

ensure_safe_dest() {
  local d="$1"
  mkdir -p "$SNAP_LKG" "$SNAP_CUR"

  local real real_lkg real_cur
  real="$(readlink -f "$d")"
  real_lkg="$(readlink -f "$SNAP_LKG")"
  real_cur="$(readlink -f "$SNAP_CUR")"

  if [[ "$real" != "$real_lkg" && "$real" != "$real_cur" ]]; then
    echo "Refusing unsafe snapshot destination: $d" >&2
    exit 3
  fi
}

command -v rsync >/dev/null 2>&1 || {
  echo "rsync is required on cenote." >&2
  exit 4
}

echo "== Connectivity check =="
ssh "${SSH_OPTS[@]}" "$K2_USER@$K2_HOST" "echo ok" >/dev/null

mkdir -p "$DEST_DIR"
ensure_safe_dest "$DEST_DIR"

if [[ "$MODE" == "current" ]]; then
  echo "== Wiping snapshot_current =="
  find "$DEST_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi

echo "== Pulling snapshot =="
echo "Host: $K2_USER@$K2_HOST"
echo "Mode: $MODE"
echo "Destination: $DEST_DIR"
echo

for src in "${INCLUDE_PATHS[@]}"; do
  rel="${src#/}"
  out="$DEST_DIR/$rel"

  mkdir -p "$out"

  echo "-- rsync: $src -> $out"
  rsync "${RSYNC_FLAGS[@]}" --info=stats2,progress2 \
    "${RSYNC_EXCLUDES[@]}" \
    -e "ssh ${SSH_OPTS[*]}" \
    "$K2_USER@$K2_HOST:$src/" \
    "$out/"
  echo
done

echo "== Writing snapshot metadata =="

REPO_GIT_COMMIT="$(git -C "$BASE_DIR" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
REPO_GIT_BRANCH="$(git -C "$BASE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo UNKNOWN)"
RUN_TS="$(date -Iseconds)"
LOCAL_HOST="$(hostname -f 2>/dev/null || hostname)"
LOCAL_USER="$(whoami)"

REMOTE_KERNEL="$(ssh "${SSH_OPTS[@]}" "$K2_USER@$K2_HOST" 'uname -a' 2>/dev/null || echo UNKNOWN)"
REMOTE_OS="$(ssh "${SSH_OPTS[@]}" "$K2_USER@$K2_HOST" 'cat /etc/openwrt_release 2>/dev/null || true' || true)"

cat > "$DEST_DIR/_snapshot_metadata.txt" <<EOF
snapshot_mode=$MODE
snapshot_timestamp=$RUN_TS

target_host=$K2_HOST
target_user=$K2_USER

runner_host=$LOCAL_HOST
runner_user=$LOCAL_USER

repo_git_branch=$REPO_GIT_BRANCH
repo_git_commit=$REPO_GIT_COMMIT

remote_uname=$REMOTE_KERNEL

remote_openwrt_release_begin
$REMOTE_OS
remote_openwrt_release_end
EOF

echo "== Snapshot complete =="
echo "$DEST_DIR"