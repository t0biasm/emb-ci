# emb-ci

Shared GitHub Actions workflows for all `emb-*` / `prj-*` repositories.

## Workflows
| Workflow | Purpose |
|---|---|
| `build-bazel.yaml` | Build a Bazel target (with submodules) and upload outputs to Artifactory |

Planned: `format-check`, `docs`, `canary` (build a reference project against a PR of a generic repo).

## Usage
Call a workflow from a project repo, **pinned by tag**; see `examples/project-ci.yaml`.

## Versioning
- `vX.Y.Z` immutable releases; floating `vX` moves only for backward-compatible changes.
- Breaking changes (renamed inputs, new required secrets) get a new major tag.
- Projects upgrade by bumping the tag in their own PR.

## Requirements
- Self-hosted runner with labels `self-hosted, linux, x64` (override with `runs-on`).
- Secrets `ARTIFACTORY_URL`, `ARTIFACTORY_USER`, `ARTIFACTORY_API_KEY` in the calling repo. `ARTIFACTORY_URL` is also passed to Bazel as `--repo_env=EMB_ARTIFACTORY_URL` (needed by `emb-toolchain`). Compiler downloads authenticate through a Bazel credential helper (`--credential_helper`) that the workflow writes from `ARTIFACTORY_USER` and `ARTIFACTORY_API_KEY` into `$RUNNER_TEMP` and deletes at the end; no `~/.netrc` is needed on the runner.
- If this repo is private: Settings -> Actions -> General -> Access -> accessible from repositories owned by the user.

## propagate (generic repos -> projects)
`.github/workflows/propagate.yaml` moves the submodule pointers of the project branches that **follow** a pushed branch/tag of a generic repository, but only when the project's CI is green with it. Example caller: `examples/propagate-caller.yaml`; scripts in `bot/`, tests `bot/test.sh`.

Who follows what is declared per project branch in `emb-project.toml` (read and checked by `tools/emb_deps.py`):
```toml
project = "prj-sumobot"

[follow."toolchain/emb-toolchain"]
track = "main"          # branch, or "tag:v1.*"
mode  = "auto"          # auto = push after green CI, pr = open a PR, off
```
Submodules that are not listed are frozen. Projects are the repositories with the topic `emb-project`; the default branch and `release/*` are considered. A release branch must not track `main` (it follows a maintained line such as `release/1.x`); such files are skipped with a warning. `group` is reserved (must share the mode) and not applied by the bot yet.

Per matching branch: the bot pushes `bot/bump-<repo>-<sha8>[-<branch>]`, the project CI builds it (the stub needs `on: push: branches: [ "bot/**" ]`) and on green the bot fast-forwards the project branch to that commit and deletes the bot branch. On red, missing CI or timeout it opens an issue in the generic repository and in the project and keeps the branch. Mode `pr` opens a pull request instead. Only fast-forward bumps are applied; one run per project branch at a time.

Setup: a GitHub App (Contents rw, Pull requests rw, Issues rw, Checks r, Metadata r) installed on the repositories, `EMB_BOT_APP_ID` (variable) and `EMB_BOT_PRIVATE_KEY` (secret) in the generic repository, and the app on the bypass list of the project's branch rulesets. The workflow runs on GitHub-hosted runners so the key never reaches the self-hosted runner.
