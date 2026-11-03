#!/usr/bin/env bash
# Targets of a canary run for a pull request of this repository: the project
# branches that follow the PR's base branch here, or the base branch of a
# repository named in a "Depends-on:" line of the PR description (the author
# must be a collaborator). Every target
# pins all involved submodules: this repository at the PR head, each dependency
# at its PR head (so the project is tested with the combination).
#
# env: GH_TOKEN OWNER SRC_NAME SRC_REF (refs/heads/<base>) PR_NUMBER PR_HEAD_SHA PR_BODY
# stdout: [{"project","branch","label","pins":[{"path","sha","fetch_ref"}]}]
set -euo pipefail
: "${OWNER:?}" "${SRC_NAME:?}" "${SRC_REF:?}" "${PR_NUMBER:?}" "${PR_HEAD_SHA:?}"
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

deps=$(printf '%s' "${PR_BODY:-}" | python3 -I "$here/../tools/depends_on.py" --owner "$OWNER")
jq -n --arg repo "$SRC_NAME" --arg base "${SRC_REF#refs/heads/}" --arg sha "$PR_HEAD_SHA" \
  --arg fetch "refs/pull/$PR_NUMBER/head" \
  '[{repo: $repo, base: $base, sha: $sha, fetch_ref: $fetch}]' > "$tmp/involved.json"

for dep in $(jq -c '.[]' <<<"$deps"); do
  repo=$(jq -r '.repo' <<<"$dep")
  number=$(jq -r '.number' <<<"$dep")
  info=$(gh api "repos/$OWNER/$repo/pulls/$number" --jq '{base: .base.ref, sha: .head.sha, author: .user.login}')
  # dependencies are built on our runner: only collaborators' pull requests count
  author=$(jq -r '.author' <<<"$info")
  perm=$(gh api "repos/$OWNER/$repo/collaborators/$author/permission" --jq '.permission' 2>/dev/null || echo none)
  case "$perm" in
    admin|maintain|write) ;;
    *) echo "error: Depends-on $repo#$number is by $author, who is no collaborator of $OWNER (permission: $perm)" >&2; exit 1 ;;
  esac
  jq --arg repo "$repo" --arg base "$(jq -r '.base' <<<"$info")" \
    --arg sha "$(jq -r '.sha' <<<"$info")" --arg fetch "refs/pull/$number/head" \
    '. + [{repo: $repo, base: $base, sha: $sha, fetch_ref: $fetch}]' \
    "$tmp/involved.json" > "$tmp/next.json"
  mv "$tmp/next.json" "$tmp/involved.json"
done

: > "$tmp/pins.jsonl"
for inv in $(jq -c '.[]' "$tmp/involved.json"); do
  repo=$(jq -r '.repo' <<<"$inv")
  base=$(jq -r '.base' <<<"$inv")
  SRC_NAME="$repo" SRC_REF="refs/heads/$base" "$here/discover.sh" > "$tmp/found.json"
  jq -c --argjson inv "$inv" \
    '.[] as $t | $t.paths[] | {project: $t.project, branch: $t.branch,
      pin: {path: ., sha: $inv.sha, fetch_ref: $inv.fetch_ref}}' \
    "$tmp/found.json" >> "$tmp/pins.jsonl"
done

jq -s 'group_by([.project, .branch]) | map({
    project: .[0].project,
    branch: .[0].branch,
    label: ((.[0].project | split("/")[1]) + "@" + .[0].branch),
    pins: map(.pin)
  })' "$tmp/pins.jsonl"
