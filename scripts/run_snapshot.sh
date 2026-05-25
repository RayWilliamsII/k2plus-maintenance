#!/usr/bin/env bash
set -euo pipefail

#if [ "$#" -ne 2 ]; then
#  echo "Usage: $0 <host> {lkg|current}" >&2
#  exit 2
#fi

HOST="$1"
#MODE="$2:-current"
MODE="${2:-current}"

if [[ "$MODE" != "lkg" && "$MODE" != "current" ]]; then
  echo "Usage1: $0 <host> {lkg|current}" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y-%m-%dT%H-%M-%S%z)"
RUN_DIR="$REPO_ROOT/runs/$HOST/${TIMESTAMP}_${MODE}"

SNAPSHOT_SCRIPT="$REPO_ROOT/scripts/snapshots/snapshot_pull.sh"

mkdir -p "$RUN_DIR"

STDOUT_FILE="$RUN_DIR/stdout.txt"
STDERR_FILE="$RUN_DIR/stderr.txt"
EXIT_FILE="$RUN_DIR/exit_code.txt"
META_FILE="$RUN_DIR/meta.json"

SCRIPT_SHA="$(sha256sum "$SNAPSHOT_SCRIPT" | awk '{print $1}')"
GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "UNKNOWN")"
RUNNER_HOST="$(hostname -f 2>/dev/null || hostname)"
RUNNER_USER="$(whoami)"

START_EPOCH="$(date +%s)"
set +e
K2_HOST="$HOST" BASE_DIR="$REPO_ROOT" "$SNAPSHOT_SCRIPT" "$MODE" \
  >"$STDOUT_FILE" \
  2>"$STDERR_FILE"
EXIT_CODE="$?"
END_EPOCH="$(date +%s)"
DURATION_SECONDS="$((END_EPOCH - START_EPOCH))"
DURATION_FORMATTED="$(printf '%02d:%02d:%02d' \
  $((DURATION_SECONDS / 3600)) \
  $(((DURATION_SECONDS % 3600) / 60)) \
  $((DURATION_SECONDS % 60)))"
set -e

echo "$EXIT_CODE" > "$EXIT_FILE"

cat > "$META_FILE" <<EOF
{
  "target_host": "$HOST",
  "snapshot_mode": "$MODE",
  "snapshot_script": "snapshot_pull.sh",
  "snapshot_script_sha256": "$SCRIPT_SHA",
  "repo_git_commit": "$GIT_COMMIT",
  "run_timestamp": "$TIMESTAMP",
  "runner_host": "$RUNNER_HOST",
  "runner_user": "$RUNNER_USER",
  "start_epoch": "$START_EPOCH",
  "end_epoch": "$END_EPOCH",
  "duration_seconds": "$DURATION_SECONDS",
  "duration_formatted": "$DURATION_FORMATTED",
  "exit_code": $EXIT_CODE
}
EOF

echo "Snapshot run complete"
echo "Host: $HOST"
echo "Mode: $MODE"
echo "Run directory: $RUN_DIR"
exit "$EXIT_CODE"