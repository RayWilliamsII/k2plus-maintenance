#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <host>" >&2
  exit 2
fi

HOST="$1"

RUN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_DIR="$RUN_ROOT/scripts/probes"
RUN_PROBE_SCRIPT="$RUN_ROOT/scripts/run_probe.sh"

if [[ ! -x "$RUN_PROBE_SCRIPT" ]]; then
  echo "Missing or non-executable run_probe.sh: $RUN_PROBE_SCRIPT" >&2
  exit 3
fi

if [[ ! -d "$PROBE_DIR" ]]; then
  echo "Missing probes directory: $PROBE_DIR" >&2
  exit 4
fi

mapfile -t PROBES < <(
  find "$PROBE_DIR" -maxdepth 1 -type f -name "*.sh" | sort
)

if [[ "${#PROBES[@]}" -eq 0 ]]; then
  echo "No probe scripts found in: $PROBE_DIR" >&2
  exit 5
fi

echo "========================================"
echo "K2 Plus Maintenance - Run All Probes"
echo "========================================"
echo
echo "Target Host: $HOST"
echo "Probe Count: ${#PROBES[@]}"
echo

FAILED=0

for probe in "${PROBES[@]}"; do
  PROBE_NAME="$(basename "$probe")"

  echo "----------------------------------------"
  echo "Running probe: $PROBE_NAME"
  echo "----------------------------------------"
  echo

  if ! "$RUN_PROBE_SCRIPT" "$HOST" "$probe"; then
    echo
    echo "ERROR: Probe failed: $PROBE_NAME"
    echo
    FAILED=1
  fi

  echo
done

echo "========================================"
echo "Probe execution complete"
echo "========================================"

if [[ "$FAILED" -ne 0 ]]; then
  echo "One or more probes failed."
  exit 10
fi

echo "All probes completed successfully."