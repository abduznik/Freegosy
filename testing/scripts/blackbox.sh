#!/usr/bin/env bash
# Private blackbox save-sync test runner.
#
# Reads credentials from testing/config/.env (git-ignored), runs the
# integration harness against the live RomM instance, and writes a
# timestamped summary to testing/data/summaries/.
#
# Usage: ./testing/scripts/blackbox.sh [platform_filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTING_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$TESTING_DIR/config/.env"
SUMMARY_DIR="$TESTING_DIR/data/summaries"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE (copy from .env.example and fill in)" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [[ -z "${ROMM_URL:-}" || -z "${ROMM_API_KEY:-}" ]]; then
  echo "ROMM_URL and ROMM_API_KEY must be set in $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$SUMMARY_DIR"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$SUMMARY_DIR/blackbox_$STAMP.log"

echo "Running blackbox save-sync tests against $ROMM_URL"
echo "Summary will be written to $LOG"
echo

ROMM_URL="$ROMM_URL" ROMM_API_KEY="$ROMM_API_KEY" \
  PLATFORM="${1:-}" \
  dart run tool/integration_tests/save_sync_integration.dart \
  2>&1 | tee "$LOG"

echo
echo "Summary: $LOG"
