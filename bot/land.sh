#!/usr/bin/env bash
# Run inside a checkout of the project repository. Brings the submodules in PATHS
# to NEW_SHA on the project branch BRANCH.
#
# MODE=pr:   bump.sh once; the workflow opens a pull request from the bump branch.
# MODE=auto: bump on top of the current origin/BRANCH, wait for the project CI,
#            and fast-forward BRANCH to the bump commit if it is still green.
#            If BRANCH moved meanwhile (another propagation landed), the bump is
#            redone on the new BRANCH and the CI runs again (MAX_ATTEMPTS).
#
# Outputs (if GITHUB_OUTPUT is set): changed, bot_branch, commit, result where
# result is one of: landed, pr, unchanged, green, red, no-ci, timeout, moved.
# Only "landed" and "pr" and "unchanged" count as success.
#
# env: NEW_SHA SRC_REPO PATHS BRANCH PROJECT MODE(auto|pr) GH_TOKEN
#      [BOT_NAME BOT_EMAIL MAX_ATTEMPTS=3]; wait-ci.sh settings pass through
set -euo pipefail
: "${NEW_SHA:?}" "${SRC_REPO:?}" "${PATHS:?}" "${BRANCH:?}" "${PROJECT:?}" "${MODE:?}"
here=$(cd "$(dirname "$0")" && pwd)
out="${GITHUB_OUTPUT:-/dev/null}"
bump_out=$(mktemp)
trap 'rm -f "$bump_out"' EXIT

result=unchanged
changed=false
bot_branch=""
commit=""

for attempt in $(seq 1 "${MAX_ATTEMPTS:-3}"); do
  git fetch --quiet origin "$BRANCH"
  git checkout -q -B "$BRANCH" "origin/$BRANCH"
  : > "$bump_out"
  GITHUB_OUTPUT="$bump_out" "$here/bump.sh"
  changed=$(sed -n 's/^changed=//p' "$bump_out" | tail -1)
  if [ "$changed" != "true" ]; then
    result=unchanged
    break
  fi
  bot_branch=$(sed -n 's/^bot_branch=//p' "$bump_out" | tail -1)
  commit=$(sed -n 's/^commit=//p' "$bump_out" | tail -1)
  if [ "$MODE" = "pr" ]; then
    result=pr
    break
  fi

  result=$(PROJECT="$PROJECT" COMMIT="$commit" "$here/wait-ci.sh")
  if [ "$result" != "green" ]; then
    break
  fi

  git fetch --quiet origin "$BRANCH"
  if git merge-base --is-ancestor "origin/$BRANCH" "$commit" \
      && git push --quiet origin "$commit:refs/heads/$BRANCH"; then
    git push --quiet origin --delete "$bot_branch"
    result=landed
    break
  fi
  echo "::notice::$BRANCH of $PROJECT moved while the CI was running (attempt $attempt), bumping on top of it"
  result=moved
done

{
  echo "changed=$changed"
  echo "bot_branch=$bot_branch"
  echo "commit=$commit"
  echo "result=$result"
} >> "$out"
echo "result: $result"
