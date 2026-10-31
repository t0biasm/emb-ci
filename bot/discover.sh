#!/usr/bin/env bash
# Print a JSON array of the project branches that follow a push to SRC_REF of
# the generic repository SRC_NAME, grouped by mode:
#   [{"project":"t0biasm/prj-x","branch":"main","mode":"auto","paths":["platform/emb-platform"]}]
#
# Projects: repositories of OWNER with topic emb-project. Branches: the default
# branch and release/*. The rules come from emb-project.toml + .gitmodules of
# each branch (tools/emb_deps.py). Branches whose file is invalid (e.g. a
# release branch tracking main) are skipped with a warning.
#
# env: GH_TOKEN OWNER SRC_NAME SRC_REF
set -euo pipefail
: "${OWNER:?}" "${SRC_NAME:?}" "${SRC_REF:?}"
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../tools/emb_deps.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
result='[]'

projects=$(gh api -X GET search/repositories \
  -f q="topic:emb-project user:$OWNER archived:false" --jq '.items[].full_name')
for project in $projects; do
  default=$(gh api "repos/$project" --jq .default_branch)
  branches=$(gh api "repos/$project/branches" --paginate --jq '.[].name' \
    | grep -E "^(${default}|release/.+)$" || true)
  for branch in $branches; do
    d="$tmp/$(printf '%s' "$project-$branch" | tr '/' '_')"
    mkdir -p "$d"
    for f in emb-project.toml .gitmodules; do
      gh api -H "Accept: application/vnd.github.raw+json" \
        "repos/$project/contents/$f?ref=$branch" > "$d/$f" 2>/dev/null || rm -f "$d/$f"
    done
    [ -f "$d/emb-project.toml" ] && [ -f "$d/.gitmodules" ] || continue
    if ! python3 "$tool" check --root "$d" --branch "$branch" 2> "$d/err"; then
      echo "::warning::$project@$branch skipped: $(tr '\n' ' ' < "$d/err")" >&2
      continue
    fi
    matches=$(python3 "$tool" match --root "$d" --repo "$SRC_NAME" --ref "$SRC_REF")
    [ "$matches" = "[]" ] && continue
    entries=$(jq -c --arg p "$project" --arg b "$branch" \
      'group_by(.mode) | map({project: $p, branch: $b, mode: .[0].mode, paths: map(.path)})' \
      <<<"$matches")
    result=$(jq -c -s 'add' <(echo "$result") <(echo "$entries"))
  done
done
echo "$result"
