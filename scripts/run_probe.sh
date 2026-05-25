#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <host> <probe_script>"
  exit 1
fi

HOST="$1"
PROBE_SCRIPT="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y-%m-%dT%H-%M-%S%z)"

PROBE_NAME="$(basename "$PROBE_SCRIPT")"
PROBE_NAME="${PROBE_NAME%.sh}"
#PROBE_NAME="$(echo "$PROBE_NAME" | tr -c 'A-Za-z0-9._-' '_')"
PROBE_NAME="$(printf '%s' "$PROBE_NAME" | tr -c 'A-Za-z0-9._-' '_')"

RUN_DIR="$REPO_ROOT/runs/$HOST/${TIMESTAMP}_${PROBE_NAME}"
#TIMESTAMP="$(date +%Y-%m-%dT%H-%M-%S%z)"
#RUN_DIR="$REPO_ROOT/runs/$HOST/$TIMESTAMP"

mkdir -p "$RUN_DIR"

STDOUT_FILE="$RUN_DIR/stdout.txt"
STDERR_FILE="$RUN_DIR/stderr.txt"
EXIT_FILE="$RUN_DIR/exit_code.txt"
META_FILE="$RUN_DIR/meta.json"

SCRIPT_BASENAME="$(basename "$PROBE_SCRIPT")"
SCRIPT_SHA="$(sha256sum "$PROBE_SCRIPT" | awk '{print $1}')"
GIT_COMMIT="$(git rev-parse HEAD)"
RUNNER_HOST="$(hostname -f 2>/dev/null || hostname)"
RUNNER_USER="$(whoami)"

# Copy probe to target (no persistence guarantee assumed)
scp -O "$PROBE_SCRIPT" "root@$HOST:/tmp/$SCRIPT_BASENAME"

START_EPOCH="$(date +%s)"
set +e
ssh "root@$HOST" "sh /tmp/$SCRIPT_BASENAME" \
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
  "probe_script": "$SCRIPT_BASENAME",
  "probe_script_sha256": "$SCRIPT_SHA",
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

echo "Probe complete:"
echo "  Host: $HOST"
echo "  Run:  $RUN_DIR"