#!/usr/bin/env bash
# Open pull requests of this repository from branches of this repository whose
# description has a "Depends-on:" line for REPO#NUMBER. Prints "<number> <head
# branch>" per line. Used to re-run their canary after a change in REPO#NUMBER.
#
# env: GH_TOKEN REPO (owner/name) NUMBER [LIMIT=100]
set -euo pipefail
: "${REPO:?}" "${NUMBER:?}"
here=$(cd "$(dirname "$0")" && pwd)
owner="${REPO%%/*}"
name="${REPO#*/}"

gh pr list -R "$REPO" --state open --limit "${LIMIT:-100}" \
    --json number,headRefName,body,isCrossRepository \
  | jq -c '.[] | select(.isCrossRepository == false)' \
  | while IFS= read -r pr; do
      body=$(jq -r '.body // ""' <<<"$pr")
      if ! deps=$(printf '%s' "$body" | python3 -I "$here/../tools/depends_on.py" --owner "$owner" 2>/dev/null); then
        continue
      fi
      if jq -e --arg repo "$name" --argjson n "$NUMBER" 'any(.repo == $repo and .number == $n)' \
          <<<"$deps" >/dev/null; then
        jq -r '"\(.number) \(.headRefName)"' <<<"$pr"
      fi
    done
