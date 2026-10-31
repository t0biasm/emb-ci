#!/usr/bin/env bash
# Run inside a checkout of the project branch. Moves the submodules in PATHS
# (JSON array) to NEW_SHA - only fast-forward - commits on a new branch
# bot/bump-<repo>-<sha8>[-<branch>] and pushes it. Outputs for GitHub Actions
# (if GITHUB_OUTPUT is set): changed, bot_branch, commit.
#
# env: NEW_SHA SRC_REPO (owner/name) PATHS BRANCH [BOT_NAME BOT_EMAIL]
set -euo pipefail
: "${NEW_SHA:?}" "${SRC_REPO:?}" "${PATHS:?}" "${BRANCH:?}"
out="${GITHUB_OUTPUT:-/dev/null}"
name="${SRC_REPO#*/}"
echo "changed=false" >> "$out"

changed=""
body=""
for path in $(jq -r '.[]' <<<"$PATHS"); do
  old=$(git rev-parse "HEAD:$path")
  if [ "$old" = "$NEW_SHA" ]; then
    echo "::notice::$path is already at $NEW_SHA"
    continue
  fi
  git submodule update --init --no-recommend-shallow -- "$path"
  git -C "$path" fetch --quiet origin "$NEW_SHA"
  git -C "$path" cat-file -e "$NEW_SHA^{commit}"
  if ! git -C "$path" merge-base --is-ancestor "$old" "$NEW_SHA"; then
    echo "::warning::$NEW_SHA is not a descendant of the pinned $old in $path, not moving (only fast-forward bumps are automatic)"
    continue
  fi
  log=$(git -C "$path" log --oneline --max-count=20 "$old..$NEW_SHA")
  git -C "$path" checkout --quiet "$NEW_SHA"
  git add "$path"
  changed="$changed $path"
  body="$body$path: ${old:0:8}..${NEW_SHA:0:8}
$log

"
done
[ -n "$changed" ] || exit 0

suffix=""
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  suffix="-$(printf '%s' "$BRANCH" | tr '/' '_')"
fi
bot_branch="bot/bump-${name}-${NEW_SHA:0:8}${suffix}"
git config user.name "${BOT_NAME:-emb-bot[bot]}"
git config user.email "${BOT_EMAIL:-emb-bot[bot]@users.noreply.github.com}"
git checkout -q -b "$bot_branch"
git commit -q -m "Bump ${name} to ${NEW_SHA:0:8}" \
  -m "$body" \
  -m "https://github.com/${SRC_REPO}/commit/${NEW_SHA}"
git push --force origin "HEAD:refs/heads/$bot_branch"
{
  echo "changed=true"
  echo "bot_branch=$bot_branch"
  echo "commit=$(git rev-parse HEAD)"
} >> "$out"
