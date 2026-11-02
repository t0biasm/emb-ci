#!/usr/bin/env bash
# Run inside a checkout of the project branch. Moves the submodules in PATHS
# (JSON array) to NEW_SHA - only fast-forward - commits on a new branch
# bot/<kind>-<repo>-<sha8>[-<branch>] and pushes it. Outputs for GitHub Actions
# (if GITHUB_OUTPUT is set): changed, bot_branch, commit.
#
# Canary builds (kind canary) use the same mechanics for a PR commit of the
# generic repository: FETCH_REF names the ref that makes NEW_SHA fetchable
# (e.g. refs/pull/<n>/head) and ALLOW_NON_FF=true skips the fast-forward check,
# because nothing is merged into the project branch.
#
# env: NEW_SHA SRC_REPO (owner/name) PATHS BRANCH [BOT_NAME BOT_EMAIL]
#      [KIND=bump|canary] [FETCH_REF=NEW_SHA] [ALLOW_NON_FF=false] [TITLE] [PINS]
set -euo pipefail
: "${NEW_SHA:?}" "${SRC_REPO:?}" "${BRANCH:?}"
if [ -z "${PINS:-}" ]; then : "${PATHS:?}"; fi
kind="${KIND:-bump}"
fetch_ref="${FETCH_REF:-$NEW_SHA}"
out="${GITHUB_OUTPUT:-/dev/null}"
name="${SRC_REPO#*/}"
echo "changed=false" >> "$out"

# PINS: JSON [{"path","sha","fetch_ref"}], one commit per submodule (canary with
# Depends-on). Default: every path of PATHS at NEW_SHA, fetched via FETCH_REF.
pins="${PINS:-}"
if [ -z "$pins" ]; then
  pins=$(jq -c --arg sha "$NEW_SHA" --arg fetch "$fetch_ref" \
    '[.[] | {path: ., sha: $sha, fetch_ref: $fetch}]' <<<"$PATHS")
fi

changed=""
body=""
while IFS= read -r pin; do
  path=$(jq -r '.path' <<<"$pin")
  sha=$(jq -r '.sha' <<<"$pin")
  fref=$(jq -r '.fetch_ref' <<<"$pin")
  old=$(git rev-parse "HEAD:$path")
  if [ "$old" = "$sha" ]; then
    echo "::notice::$path is already at $sha"
    continue
  fi
  git submodule update --init --no-recommend-shallow -- "$path"
  git -C "$path" fetch --quiet origin "$fref"
  git -C "$path" cat-file -e "$sha^{commit}"
  if [ "${ALLOW_NON_FF:-false}" != "true" ] \
      && ! git -C "$path" merge-base --is-ancestor "$old" "$sha"; then
    echo "::warning::$sha is not a descendant of the pinned $old in $path, not moving (only fast-forward bumps are automatic)"
    continue
  fi
  log=$(git -C "$path" log --oneline --max-count=20 "$old..$sha")
  git -C "$path" checkout --quiet "$sha"
  git add "$path"
  changed="$changed $path"
  body="$body$path: ${old:0:8}..${sha:0:8}
$log

"
done < <(jq -c '.[]' <<<"$pins")
[ -n "$changed" ] || exit 0

suffix=""
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  suffix="-$(printf '%s' "$BRANCH" | tr '/' '_')"
fi
bot_branch="bot/${kind}-${name}-${NEW_SHA:0:8}${suffix}"
git config user.name "${BOT_NAME:-emb-bot[bot]}"
git config user.email "${BOT_EMAIL:-emb-bot[bot]@users.noreply.github.com}"
git checkout -q -B "$bot_branch"
git commit -q -m "${TITLE:-Bump ${name} to ${NEW_SHA:0:8}}" \
  -m "$body" \
  -m "https://github.com/${SRC_REPO}/commit/${NEW_SHA}"
git push --force origin "HEAD:refs/heads/$bot_branch"
{
  echo "changed=true"
  echo "bot_branch=$bot_branch"
  echo "commit=$(git rev-parse HEAD)"
} >> "$out"
