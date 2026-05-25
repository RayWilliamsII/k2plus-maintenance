#!/usr/bin/env bash
set -euo pipefail

K2_HOST="${K2_HOST:-k2plus.local}"
K2_USER="${K2_USER:-root}"
BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

MODE="${1:-current}"
if [[ "$MODE" != "lkg" && "$MODE" != "current" ]]; then
  echo "Usage: $0 [lkg|current]" >&2
  exit 2
fi

SNAP_LKG="$BASE_DIR/snapshot_lkg"
SNAP_CUR="$BASE_DIR/snapshot_current"

if [[ "$MODE" == "lkg" ]]; then
  DEST_DIR="$SNAP_LKG"
else
  DEST_DIR="$SNAP_CUR"
fi

SNAPSHOT_EXCLUDES_FILE="$BASE_DIR/config/snapshot_excludes.default.tsv"
SNAPSHOT_PATHS_FILE="$BASE_DIR/config/snapshot_paths.default.tsv"

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

RRSYNC_EXCLUDES=()

if [[ -f "$SNAPSHOT_EXCLUDES_FILE" ]]; then
  while IFS=$'\t' read -r exclude_pattern exclude_description; do
    [[ -z "${exclude_pattern:-}" ]] && continue
    [[ "$exclude_pattern" =~ ^# ]] && continue

    RSYNC_EXCLUDES+=("--exclude=$exclude_pattern")
  done < "$SNAPSHOT_EXCLUDES_FILE"
else
  echo "No snapshot excludes config found: $SNAPSHOT_EXCLUDES_FILE"
  echo "Continuing without configured excludes."
fi

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

clear_snapshot_dest() {
  local d="$1"

  if find "$d" -mindepth 1 -maxdepth 1 | read -r _; then
    local prompt_target="/dev/tty"

    if [ ! -w "$prompt_target" ] || [ ! -r "$prompt_target" ]; then
      prompt_target="/dev/stderr"
    fi

    {
      echo
      echo "========================================"
      echo "WARNING: Snapshot directory is not empty"
      echo "========================================"
      echo
      echo "Target:"
      echo "  $d"
      echo
      echo "Its contents will be permanently removed."
      echo
      printf "Proceed? [y/N]: "
    } >"$prompt_target"

    read -r reply <"$prompt_target"

    if [[ "$reply" != "y" ]]; then
      echo "Aborted by user." >"$prompt_target"
      exit 10
    fi

    echo
    echo "== Clearing existing snapshot contents =="
    find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
}

command -v rsync >/dev/null 2>&1 || {
  echo "rsync is required on cenote." >&2
  exit 4
}

if [[ ! -f "$SNAPSHOT_PATHS_FILE" ]]; then
  echo "Missing snapshot path config: $SNAPSHOT_PATHS_FILE" >&2
  exit 5
fi

echo "== Connectivity check =="
ssh "${SSH_OPTS[@]}" "$K2_USER@$K2_HOST" "echo ok" >/dev/null

mkdir -p "$DEST_DIR"
ensure_safe_dest "$DEST_DIR"
clear_snapshot_dest "$DEST_DIR"

echo "== Pulling snapshot =="
echo "Host: $K2_USER@$K2_HOST"
echo "Mode: $MODE"
echo "Destination: $DEST_DIR"
echo "Snapshot path config: $SNAPSHOT_PATHS_FILE"
echo

while IFS=$'\t' read -r disposition src description; do
  [[ -z "${disposition:-}" ]] && continue
  [[ "$disposition" =~ ^# ]] && continue

  description="${description:-}"

  case "$disposition" in
    required|optional|informational) ;;
    *)
      echo "Invalid snapshot path disposition: $disposition for path: ${src:-}" >&2
      exit 6
      ;;
  esac

  if [[ -z "${src:-}" ]]; then
    echo "Invalid snapshot config row: missing path" >&2
    exit 6
  fi

  echo "-- path: $src"
  echo "   disposition: $disposition"
  if [[ -n "$description" ]]; then
    echo "   description: $description"
  fi

  if [[ "$disposition" == "informational" ]]; then
    echo "   action: informational only; not copied"
    echo
    continue
  fi

  rel="${src#/}"
  out="$DEST_DIR/$rel"

  echo "   action: checking remote path"
  if ! ssh "${SSH_OPTS[@]}" "$K2_USER@$K2_HOST" "[ -e '$src' ]"; then
    if [[ "$disposition" == "required" ]]; then
      echo "ERROR: required snapshot path is missing: $src" >&2
      if [[ -n "$description" ]]; then
        echo "Description: $description" >&2
      fi
      exit 7
    fi

    echo "   action: skipping missing optional path"
    echo
    continue
  fi

  mkdir -p "$out"

  echo "   action: rsync to $out"
  rsync "${RSYNC_FLAGS[@]}" --info=stats2,progress2 \
    "${RSYNC_EXCLUDES[@]}" \
    -e "ssh ${SSH_OPTS[*]}" \
    "$K2_USER@$K2_HOST:$src/" \
    "$out/"
  echo
done < "$SNAPSHOT_PATHS_FILE"

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

snapshot_excludes_file=$SNAPSHOT_EXCLUDES_FILE
snapshot_paths_file=$SNAPSHOT_PATHS_FILE

remote_uname=$REMOTE_KERNEL

remote_openwrt_release_begin
$REMOTE_OS
remote_openwrt_release_end
EOF

echo "== Snapshot complete =="
echo "$DEST_DIR"