#!/usr/bin/env bash
# Wait for the check runs of COMMIT in PROJECT and print green, red, no-ci or
# timeout. env: GH_TOKEN PROJECT COMMIT [START_DELAY=30 POLL=20 APPEAR=600 TIMEOUT=3600]
set -euo pipefail
: "${PROJECT:?}" "${COMMIT:?}"
sleep "${START_DELAY:-30}"
poll="${POLL:-20}"
appear=$((SECONDS + ${APPEAR:-600}))
deadline=$((SECONDS + ${TIMEOUT:-3600}))
stable=0
while true; do
  json=$(gh api "repos/$PROJECT/commits/$COMMIT/check-runs" \
    --jq '[.check_runs[] | {status, conclusion}]')
  total=$(jq length <<<"$json")
  pending=$(jq '[.[] | select(.status != "completed")] | length' <<<"$json")
  if [ "$total" -gt 0 ] && [ "$pending" -eq 0 ]; then
    stable=$((stable + 1))
    [ "$stable" -ge 2 ] && break
  else
    stable=0
  fi
  if [ "$total" -eq 0 ] && [ "$SECONDS" -gt "$appear" ]; then echo no-ci; exit 0; fi
  if [ "$SECONDS" -gt "$deadline" ]; then echo timeout; exit 0; fi
  sleep "$poll"
done
bad=$(jq '[.[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | length' <<<"$json")
if [ "$bad" -eq 0 ]; then echo green; else echo red; fi
