#!/usr/bin/env bash
# Local tests of discover.sh (with a gh shim) and bump.sh (with local git repos).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
export GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=test
export GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
fail() { echo "FAIL: $*" >&2; exit 1; }

# ---------------- discover.sh ----------------
mkdir -p "$tmp/shim"
fx="$tmp/fx"; mkdir -p "$fx"
GM='[submodule "platform/emb-platform"]
	path = platform/emb-platform
	url = https://github.com/t0biasm/emb-platform.git'
printf '%s\n' "$GM" > "$fx/gitmodules"
printf 'project = "p"\n[follow."platform/emb-platform"]\ntrack = "main"\n' > "$fx/main.toml"
printf 'project = "p"\n[follow."platform/emb-platform"]\ntrack = "release/1.x"\nmode = "pr"\n' > "$fx/release_1.0.toml"
printf 'project = "p"\n[follow."platform/emb-platform"]\ntrack = "main"\n' > "$fx/release_0.9.toml"
cat > "$tmp/shim/gh" <<SHIM
#!/usr/bin/env bash
a="\$*"
case "\$a" in
  *search/repositories*) echo t0biasm/prj-a ;;
  *"repos/t0biasm/prj-a --jq"*) echo main ;;
  *"repos/t0biasm/prj-a/branches"*) printf 'main\nrelease/1.0\nrelease/0.9\nfeature/x\n' ;;
  *contents/.gitmodules*) cat "$fx/gitmodules" ;;
  *contents/emb-project.toml*ref=*)
    b="\${a##*ref=}"; b="\${b//\//_}"; cat "$fx/\$b.toml" ;;
  *) echo "unexpected gh call: \$a" >&2; exit 1 ;;
esac
SHIM
chmod +x "$tmp/shim/gh"
export PATH="$tmp/shim:$PATH" OWNER=t0biasm SRC_NAME=emb-platform
out=$(SRC_REF=refs/heads/main "$here/discover.sh" 2>/dev/null)
[ "$(jq -c . <<<"$out")" = '[{"project":"t0biasm/prj-a","branch":"main","mode":"auto","paths":["platform/emb-platform"]}]' ] \
  || fail "discover main: $out"
out=$(SRC_REF=refs/heads/release/1.x "$here/discover.sh" 2>/dev/null)
[ "$(jq -c . <<<"$out")" = '[{"project":"t0biasm/prj-a","branch":"release/1.0","mode":"pr","paths":["platform/emb-platform"]}]' ] \
  || fail "discover release: $out"
out=$(SRC_REF=refs/heads/other "$here/discover.sh" 2>/dev/null)
[ "$out" = "[]" ] || fail "discover other: $out"
echo "discover.sh ok"

# ---------------- bump.sh ----------------
git init -q --bare -b main "$tmp/gen.git"
git clone -q "$tmp/gen.git" "$tmp/gen"
( cd "$tmp/gen"; git checkout -q -b main
  echo 1 > f; git add f; git commit -q -m c1; c1=$(git rev-parse HEAD)
  echo 2 > f; git commit -q -am c2; git push -q origin main
  git checkout -q -b other "$c1"; echo x > g; git add g; git commit -q -m diverged
  git push -q origin other ) 
c1=$(git -C "$tmp/gen" rev-parse main~1); c2=$(git -C "$tmp/gen" rev-parse main)
div=$(git -C "$tmp/gen" rev-parse other)

git init -q --bare -b main "$tmp/proj.git"
git clone -q "$tmp/proj.git" "$tmp/proj"
( cd "$tmp/proj"; git checkout -q -b main
  git submodule add -q "$tmp/gen.git" platform/emb-platform
  git -C platform/emb-platform checkout -q "$c1"
  git add -A; git commit -q -m init; git push -q origin main )
git clone -q --recurse-submodules "$tmp/proj.git" "$tmp/work"

cd "$tmp/work"
export GITHUB_OUTPUT="$tmp/out"; : > "$GITHUB_OUTPUT"
: > "$GITHUB_OUTPUT"
NEW_SHA=$c2 SRC_REPO=t0biasm/emb-platform PATHS='["platform/emb-platform"]' BRANCH=main "$here/bump.sh" >/dev/null
grep -q 'changed=true' "$GITHUB_OUTPUT" || fail "fast-forward bump expected"
bb=$(sed -n 's/^bot_branch=//p' "$GITHUB_OUTPUT")
[ "$bb" = "bot/bump-emb-platform-${c2:0:8}" ] || fail "branch name $bb"
pinned=$(git --git-dir="$tmp/proj.git" ls-tree "$bb" platform/emb-platform | awk '{print $3}')
[ "$pinned" = "$c2" ] || fail "pinned $pinned != $c2"
git --git-dir="$tmp/proj.git" log -1 --format=%B "$bb" | grep -q "c2" || fail "changelog missing"
[ "$(git --git-dir="$tmp/proj.git" rev-parse main)" != "$(git --git-dir="$tmp/proj.git" rev-parse "$bb")" ] || fail "main must not move"

# on the bump branch (pinned at c2): same commit again and a diverged commit -> nothing to do
git checkout -q "$bb"; git submodule update -q; : > "$GITHUB_OUTPUT"
NEW_SHA=$c2 SRC_REPO=t0biasm/emb-platform PATHS='["platform/emb-platform"]' BRANCH=main "$here/bump.sh" >/dev/null 2>&1
grep -q 'changed=true' "$GITHUB_OUTPUT" && fail "no change expected"

: > "$GITHUB_OUTPUT"
NEW_SHA=$div SRC_REPO=t0biasm/emb-platform PATHS='["platform/emb-platform"]' BRANCH=main "$here/bump.sh" >/dev/null 2>&1
grep -q 'changed=true' "$GITHUB_OUTPUT" && fail "non-fast-forward must not bump"
echo "bump.sh non-fast-forward ok"

# canary: a non-fast-forward commit is built on a canary branch, main does not move
: > "$GITHUB_OUTPUT"
KIND=canary ALLOW_NON_FF=true FETCH_REF=refs/heads/other TITLE="Canary: emb-platform PR #1" \
  NEW_SHA=$div SRC_REPO=t0biasm/emb-platform PATHS='["platform/emb-platform"]' BRANCH=main "$here/bump.sh" >/dev/null
grep -q 'changed=true' "$GITHUB_OUTPUT" || fail "canary must accept a non-fast-forward commit"
cb=$(sed -n 's/^bot_branch=//p' "$GITHUB_OUTPUT")
[ "$cb" = "bot/canary-emb-platform-${div:0:8}" ] || fail "canary branch name $cb"
pinned=$(git --git-dir="$tmp/proj.git" ls-tree "$cb" platform/emb-platform | awk '{print $3}')
[ "$pinned" = "$div" ] || fail "canary pinned $pinned != $div"
[ "$(git --git-dir="$tmp/proj.git" log -1 --format=%s "$cb")" = "Canary: emb-platform PR #1" ] || fail "canary title"
[ "$(git --git-dir="$tmp/proj.git" rev-parse main)" != "$(git --git-dir="$tmp/proj.git" rev-parse "$cb")" ] || fail "canary must not move main"
echo "bump.sh canary ok"

# land.sh: auto mode with a project main that moves while the CI runs
mkdir -p "$tmp/shim2"
cat > "$tmp/shim2/gh" <<'SHIM'
#!/usr/bin/env bash
# only wait-ci.sh calls gh here: optionally land a commit on the project's main
# once (simulating a concurrent propagation), then report one completed check
if [ -f "$TEST_TMP/hook_pending" ]; then
  rm -f "$TEST_TMP/hook_pending"
  git -C "$TEST_TMP/other" push -q origin HEAD:main
fi
echo "[{\"status\":\"completed\",\"conclusion\":\"${SHIM_CONCL:-success}\"}]"
SHIM
chmod +x "$tmp/shim2/gh"
export TEST_TMP="$tmp"
git clone -q --recurse-submodules "$tmp/proj.git" "$tmp/land"
git clone -q "$tmp/proj.git" "$tmp/other"
git -C "$tmp/other" checkout -q main
echo extra > "$tmp/other/f2"; git -C "$tmp/other" add f2; git -C "$tmp/other" commit -q -m "other propagation"
touch "$tmp/hook_pending"
cd "$tmp/land"
export PATH="$tmp/shim2:$PATH" MODE=auto PROJECT=t0biasm/prj-x GH_TOKEN=x START_DELAY=0 POLL=0 TIMEOUT=60
export NEW_SHA=$c2 SRC_REPO=t0biasm/emb-platform PATHS='["platform/emb-platform"]' BRANCH=main
export GITHUB_OUTPUT="$tmp/land_out"; : > "$GITHUB_OUTPUT"
"$here/land.sh" >/dev/null
grep -q '^result=landed$' "$GITHUB_OUTPUT" || fail "land after a moved main: $(cat "$GITHUB_OUTPUT")"
pinned=$(git --git-dir="$tmp/proj.git" ls-tree main platform/emb-platform | awk '{print $3}')
[ "$pinned" = "$c2" ] || fail "landed pin $pinned != $c2"
git --git-dir="$tmp/proj.git" cat-file -e main:f2 || fail "landed main lost the concurrent commit"
[ -z "$(git ls-remote "$tmp/proj.git" "refs/heads/bot/bump-emb-platform-${c2:0:8}")" ] || fail "bump branch not deleted after landing"
echo "land.sh moved main ok"

# land.sh: red CI never moves main; the bump branch is kept
git -C "$tmp/gen" checkout -q main; echo 3 > "$tmp/gen/f"; git -C "$tmp/gen" commit -q -am c3; git -C "$tmp/gen" push -q origin main
c3=$(git -C "$tmp/gen" rev-parse main)
export NEW_SHA=$c3 SHIM_CONCL=failure
: > "$GITHUB_OUTPUT"
"$here/land.sh" >/dev/null
grep -q '^result=red$' "$GITHUB_OUTPUT" || fail "red CI result: $(cat "$GITHUB_OUTPUT")"
pinned=$(git --git-dir="$tmp/proj.git" ls-tree main platform/emb-platform | awk '{print $3}')
[ "$pinned" = "$c2" ] || fail "red CI moved main to $pinned"
[ -n "$(git ls-remote "$tmp/proj.git" "refs/heads/bot/bump-emb-platform-${c3:0:8}")" ] || fail "bump branch of red CI not kept"
echo "land.sh red ok"
