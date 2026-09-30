# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## What this is

A composite GitHub Action (`action.yml`) that builds and pushes a Docker image, then commits the new image tag to a GitOps repo (default `Staffbase/mops`) so Flux rolls it out. All logic lives in Bash scripts under `scripts/`; `action.yml` only wires inputs to them via `INPUT_*` env vars and gates steps on their outputs.

## Commands

Tooling is pinned in `mise.toml` (bats, shellcheck). `yq` is needed for the GitOps tests (they skip without it).

```bash
mise run lint     # shellcheck --severity=warning on scripts/*.sh scripts/lib/*.sh
mise run test     # clones bats-support/bats-assert into tests/test_helper/ once, then runs all tests
mise run check    # lint + test

bats tests/generate-tags.bats                      # single file (after `mise run test` installed helpers)
bats tests/generate-tags.bats -f "main branch"     # single test by name regex
```

CI (`.github/workflows/ci.yml`) additionally checks that every script referenced in `action.yml` via `github.action_path` exists and that every `scripts/**/*.sh` is executable — `chmod +x` new scripts.

## Architecture

Step flow in `action.yml`:

1. `generate-tags.sh` — central decision point. From `GITHUB_REF` it computes `tag`, `tag_list`, `gitops_tag`, `latest`, `push`, `build`, the primary registry and whether credentials exist. Most later steps gate on these outputs.
   - `dev`/`main`/`master` branches: timestamped tag `<prefix>-<UTC ts>-<sha8>` (sortable for Flux) plus alias `<prefix>-<sha8>`. `docker-tag-timestamp: false` gives only the legacy alias.
   - `v*` / other tags and `docker-custom-tag`: `build=false` (unless `docker-disable-retagging`), i.e. no rebuild — the image built on main is retagged.
   - Other refs: build only, `push=false`.
   - `gitops_tag` is always the non-timestamped tag, so separate action invocations agree on what goes into the GitOps repo.
2. `resolve-build-config.sh` / `verify-architecture.sh` — platforms, cache scope and outputs, incl. multi-arch handling.
3. `login-registries.sh` → `docker/build-push-action`.
4. Multi-arch (`multiarch-mode`): `build` jobs push by digest and upload digest artifacts; one `merge` job runs `merge-manifests.sh` and then does the GitOps/Upwind steps. `build` mode skips all GitOps steps.
5. `retag-image.sh` (release/custom tag path) — polls the primary registry's v2 manifest API for the `main-<sha8>`/`master-<sha8>` image, retags it, then replicates to additional registries with `docker buildx imagetools create`.
6. `update-gitops.sh` — checks out the GitOps repo and edits YAML with `yq`. Environment by ref: `main`/`master` → `gitops-stage`, `dev` → `gitops-dev`, tags → `gitops-prod`; any other ref simulates the dev update without committing. Each input line is `<file> <yq-path>`; a path ending in `.tag` or pointing at a map with `tag`/`repository` gets only the tag, otherwise the full image reference. Also stamps `<deployment-domain>/…` annotations. Commit + push retries with backoff.

Shared libs in `scripts/lib/` (sourced, never executed):
- `common.sh` — `set -euo pipefail`, `log_*` (GitHub `::notice::`/`::error::` annotations), `set_output` (handles multi-line heredoc form), `require_env`, `retry_with_backoff`, `reverse_domain`.
- `registries.sh` — parses `docker-registries` (newline list of `registry[|user[|password]]`, first entry = primary) into the `REGISTRIES` array; `registry_field` reads columns. Partial credentials across registries is a hard error.
- `gitops-functions.sh` — yq update/commit/push helpers.

## Conventions

- Each script starts with a header comment listing required/optional env vars and outputs — keep it in sync when changing inputs.
- Scripts read inputs only from `INPUT_*` env vars (never inline `${{ }}` in `run:`) and write outputs only via `set_output`.
- Tests: one `tests/<script>.bats` per script (`lib-*.bats` for libs). They `load 'test_helper/setup'`, call `setup_common`/`teardown_common`, stub external commands (`curl`, `docker`, `git`) by placing mocks first on `PATH`, and assert `GITHUB_OUTPUT` values with `assert_output_value`. Use `BUILD_TIMESTAMP` to pin tag timestamps.
- Third-party actions are pinned to a commit SHA with a version comment.
- New or changed inputs must be reflected in `README.md` (Inputs table and usage sections).

## Commits

- Conventional commits, ticket as scope when one exists: `feat(DEVS-1547): support pushing images to multiple registries`, `fix(DEVS-1547): ...`, `docs(...)`, `test(...)`. Without a ticket use a plain type or a component scope: `chore: ...`, `fix(action): ...`.
- Lowercase imperative subject, no trailing period. One logical change per commit; tests go in the same commit as the code they cover.
- Branch off `main`, named `<TICKET>-<short-title>` (no slashes) or a descriptive name when untracked.

## Pull Requests

- Open as draft. PR title follows the commit convention (it becomes the Release Drafter changelog line).
- Fill in `.github/PULL_REQUEST_TEMPLATE.md` (type of change, description, checklist). Put the Jira link at the top of the description when there is a ticket.
- Labels drive the next version (`.github/release-drafter.yml`): `feature` bumps **major**, `enhancement` minor, `fix`/`bug`/`chore`/`dependencies` patch. Pick `enhancement` for backwards-compatible new inputs; reserve `feature` for changes that break existing callers.

## Releasing

Release Drafter (`.github/release-drafter.yml`) builds a draft release from merged PRs. Publish the draft with a new version, then move the floating major version tag to the release commit.
