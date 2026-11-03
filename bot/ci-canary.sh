#!/usr/bin/env bash
# Run inside a checkout of a project's default branch. Points the reusable
# emb-ci workflow calls of the project (uses: <SRC_REPO>/.github/workflows/...@<ref>)
# at NEW_SHA and commits this on bot/ci-canary-<repo>-<sha8>, which is force-pushed.
# The project CI builds it (push trigger on bot/**). Outputs for GitHub Actions
# (if GITHUB_OUTPUT is set): changed, bot_branch, commit.
#
# env: NEW_SHA SRC_REPO (owner/emb-ci) BRANCH [BOT_NAME BOT_EMAIL]
set -euo pipefail
: "${NEW_SHA:?}" "${SRC_REPO:?}" "${BRANCH:?}"
out="${GITHUB_OUTPUT:-/dev/null}"
name="${SRC_REPO#*/}"
echo "changed=false" >> "$out"

for f in .github/workflows/*.yaml .github/workflows/*.yml; do
  [ -f "$f" ] || continue
  sed -i -E "s#(uses:[[:space:]]*${SRC_REPO}/\.github/workflows/[^@[:space:]]+)@[^[:space:]]+#\1@${NEW_SHA}#" "$f"
done
if git diff --quiet; then
  echo "::notice::the workflows of $BRANCH already use $NEW_SHA (or do not call $SRC_REPO)"
  exit 0
fi

bot_branch="bot/ci-canary-${name}-${NEW_SHA:0:8}"
git config user.name "${BOT_NAME:-emb-bot[bot]}"
git config user.email "${BOT_EMAIL:-emb-bot[bot]@users.noreply.github.com}"
git checkout -q -B "$bot_branch"
git commit -q -am "${TITLE:-Canary: ${SRC_REPO} workflows at ${NEW_SHA:0:8}}"
git push --force --quiet origin "HEAD:refs/heads/$bot_branch"
{
  echo "changed=true"
  echo "bot_branch=$bot_branch"
  echo "commit=$(git rev-parse HEAD)"
} >> "$out"
