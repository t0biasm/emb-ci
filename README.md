# emb-ci

Shared GitHub Actions workflows for all `emb-*` / `prj-*` repositories.

## Workflows
| Workflow | Purpose |
|---|---|
| `.github/actions/project-build` | Composite action: build a project's Bazel target with its `[ci]` settings and upload the outputs to Artifactory (used by the project stub `examples/project-ci.yaml`) |
| `canary.yaml` | Generic canary: build the projects that follow a PR's repository with the PR commit |
| `propagate.yaml` | Generic propagation: move the submodule pointers of the projects after a push |
| `canary-self.yaml`, `propagate-self.yaml` | Callers of canary and propagation for this repository |

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
`.github/workflows/propagate.yaml` moves the submodule pointers of the project branches that **follow** a pushed branch/tag of a generic repository, but only when the project's CI is green with it. Example caller: `examples/propagate-caller.yaml`; scripts in `bot/`, tests `bot/test.sh`. If the project branch moved while its CI ran (another propagation landed), the bump is redone on top of it and the CI runs again (`bot/land.sh`, up to 3 attempts).

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

## canary (generic repos -> projects, on pull requests)
`.github/workflows/canary.yaml` builds, for each pull request of a generic repository, the project branches that follow its base branch, with the submodule pointing at the PR's head commit. Each project build is a check `canary / ci / <project>@<branch>` in the PR (the target label is shown); `canary / ci / gate` is the one to make required, with the caller job id `ci`. The canary branch in the project (`bot/canary-<repo>-<sha8>`) is deleted afterwards; nothing is merged. Only pull requests from the same repository are built (no secrets for forks). Example caller: `examples/canary-caller.yaml`.

**Depends-on:** a line `Depends-on: https://github.com/<owner>/<repo>/pull/<n>` in the PR description (same owner; the dependency must be by a collaborator) adds that PR's head to the pins, so the projects are built with both changes. Editing the description re-runs the canary. After a new commit or edit of a PR, the canary of every open PR of the same repository that depends on it is re-run too (not for dependencies in other generic repositories yet).

## Project setup with the submodule
A project takes emb-ci as the submodule `emb-ci` and copies `examples/project-ci.yaml` to `.github/workflows/ci.yaml` (identical in every project). The project's own settings are the `[ci]` table of `emb-project.toml`, checked by `tools/emb_deps.py`:

```toml
project = "prj-sumobot"

[ci]
target = "//applications/sumobot:app"    # required
config = "atmega32u4"                    # default: "" (no --config)
artifact-patterns = "*.hex *.elf *.bin app"   # default: "*.hex *.elf *.bin *.out"
submodules = "true"                      # false | true | recursive, default recursive
upload = true                            # default true
```

The build itself is the composite action `.github/actions/project-build`, which reads these settings with `emb_deps.py ci-settings`.

## Generic checks for emb-ci itself
`canary-self.yaml` and `propagate-self.yaml` call the generic canary and propagation (`canary.yaml`, `propagate.yaml`) of this repository, like the other generic repositories. Projects that follow `emb-ci` get the new commit this way. The required check of `main` is `ci / gate`.
