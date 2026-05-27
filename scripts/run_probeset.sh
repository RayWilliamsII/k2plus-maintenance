#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <host> <probeset>" >&2
  echo "Example: $0 k2plus.local abbrev" >&2
  exit 2
fi

HOST="$1"
PROBESET="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_ROOT/config"
PROBE_DIR="$REPO_ROOT/scripts/probes"
RUN_PROBE_SCRIPT="$REPO_ROOT/scripts/run_probe.sh"
PROBESET_FILE="$CONFIG_DIR/probeset.${PROBESET}.tsv"

if [[ ! -x "$RUN_PROBE_SCRIPT" ]]; then
  echo "Missing or non-executable run_probe.sh: $RUN_PROBE_SCRIPT" >&2
  exit 3
fi

if [[ ! -d "$PROBE_DIR" ]]; then
  echo "Missing probes directory: $PROBE_DIR" >&2
  exit 4
fi

if [[ ! -f "$PROBESET_FILE" ]]; then
  echo "Missing probeset file: $PROBESET_FILE" >&2
  exit 5
fi

echo "========================================"
echo "K2 Plus Maintenance - Run Probe Set"
echo "========================================"
echo
echo "Target Host: $HOST"
echo "Probe Set:   $PROBESET"
echo "Config File: $PROBESET_FILE"
echo

FAILED=0

while IFS=$'\t' read -r NAME SCRIPT_FILE_NAME; do
 
  if [[ -z "${SCRIPT_FILE_NAME:-}" ]]; then
    echo "Invalid probeset row: missing ScriptFileName for probe '$NAME'" >&2
    FAILED=1
    continue
  fi

  PROBE_SCRIPT="$PROBE_DIR/$SCRIPT_FILE_NAME"

  if [[ ! -f "$PROBE_SCRIPT" ]]; then
    echo "ERROR: Probe script not found: $PROBE_SCRIPT" >&2
    FAILED=1
    continue
  fi

  echo "----------------------------------------"
  echo "Probe:   $NAME"
  echo "Script:  $SCRIPT_FILE_NAME"
  echo "----------------------------------------"
  echo

  if ! "$RUN_PROBE_SCRIPT" "$HOST" "$PROBE_SCRIPT" </dev/null; then
    echo
    echo "ERROR: Probe failed: $SCRIPT_FILE_NAME" >&2
    FAILED=1
  fi

  echo
done < "$PROBESET_FILE"

echo "========================================"
echo "Probe set execution complete"
echo "========================================"

if [[ "$FAILED" -ne 0 ]]; then
  echo "One or more probes failed." >&2
  exit 10
fi

echo "All probes completed successfully."