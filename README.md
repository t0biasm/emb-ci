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
