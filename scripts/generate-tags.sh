#!/usr/bin/env bash
# Generates Docker image tags based on the current Git ref.
#
# Required env vars: GITHUB_REF, GITHUB_SHA, INPUT_DOCKER_REGISTRIES, INPUT_DOCKER_IMAGE
# Optional env vars: INPUT_DOCKER_CUSTOM_TAG, INPUT_DOCKER_DISABLE_RETAGGING,
#                    INPUT_DOCKER_TAG_TIMESTAMP, INPUT_DOCKER_TAG_KEEP_V_PREFIX
#
# Outputs (via GITHUB_OUTPUT): build, latest, push, tag, tag_list, gitops_tag,
#                    primary_registry, primary_registry_api, has_credentials

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/registries.sh
source "${SCRIPT_DIR}/lib/registries.sh"

require_env GITHUB_REF
require_env GITHUB_SHA
require_env INPUT_DOCKER_REGISTRIES
require_env INPUT_DOCKER_IMAGE

resolve_registries
PRIMARY_REGISTRY="$(registry_field "${REGISTRIES[0]}" 1)"
# Standard Docker Registry HTTP API v2 form, derived from the primary's bare
# host (stripping any path prefix, same as the login step). Used as the
# default for docker-registry-api, so reordering docker-registries to change
# the primary also moves where release-retag looks without a second input to
# keep in sync.
PRIMARY_REGISTRY_API="https://${PRIMARY_REGISTRY%%/*}/v2/"

# HAS_CREDENTIALS is true when every configured registry resolved a username
# and password (its own, or the top-level fallback). Steps further down the
# action (buildx setup, login, build) gate on this instead of the raw
# top-level docker-username/docker-password, since docker-registries lets
# every entry carry its own, fully independent credentials. A registry list
# with some entries credentialed and others not is a misconfiguration, not a
# valid "skip push" state — it would otherwise let buildx attempt an
# unauthenticated push to whichever entries login-registries.sh skipped, so
# it fails fast instead.
CONFIGURED_CREDENTIALS=0
MISSING_CREDENTIALS=()
for registry_entry in "${REGISTRIES[@]}"; do
  if [[ -n "$(registry_field "$registry_entry" 2)" && -n "$(registry_field "$registry_entry" 3)" ]]; then
    CONFIGURED_CREDENTIALS=$((CONFIGURED_CREDENTIALS + 1))
  else
    MISSING_CREDENTIALS+=("$(registry_field "$registry_entry" 1)")
  fi
done

if [[ $CONFIGURED_CREDENTIALS -gt 0 && ${#MISSING_CREDENTIALS[@]} -gt 0 ]]; then
  log_error "docker-registries has credentials for some registries but not: ${MISSING_CREDENTIALS[*]}. Give every registry its own username/password, or a top-level docker-username/docker-password fallback."
  exit 1
fi

HAS_CREDENTIALS="false"
[[ $CONFIGURED_CREDENTIALS -gt 0 ]] && HAS_CREDENTIALS="true"

BUILD="true"
# ALIAS_TAG is an additional immutable tag pushed alongside TAG (see set_branch_tags).
ALIAS_TAG=""

# set_branch_tags computes the immutable tag(s) for an environment branch and
# assigns them to the globals TAG and ALIAS_TAG.
#
# By default (INPUT_DOCKER_TAG_TIMESTAMP unset or "true") the canonical TAG gets a
# UTC timestamp inserted before the short SHA (e.g. dev-20260602143055-abcdef12).
# This makes branch tags sortable by Flux image automation (numerical policy) — the
# Git SHA alone is not orderable, so Flux cannot otherwise tell which build is
# newest. In that case ALIAS_TAG holds the legacy <prefix>-<short-sha> tag, which is
# also pushed: it is the stable per-commit handle that retag-image.sh looks up to
# find the source image for a release, so dropping it would break the release retag.
# The alias does not match Flux's "<prefix>-<digits>-<hex>" pattern, so Flux
# ignores it. Set INPUT_DOCKER_TAG_TIMESTAMP="false" to opt out and produce only the
# legacy <prefix>-<short-sha> tag.
#
# The timestamp is overridable via BUILD_TIMESTAMP for deterministic tests.
set_branch_tags() {
  local prefix="$1"
  local sha="${GITHUB_SHA::8}"
  if [[ "${INPUT_DOCKER_TAG_TIMESTAMP:-true}" == "true" ]]; then
    local ts="${BUILD_TIMESTAMP:-$(date -u +%Y%m%d%H%M%S)}"
    TAG="${prefix}-${ts}-${sha}"
    ALIAS_TAG="${prefix}-${sha}"
  else
    TAG="${prefix}-${sha}"
    ALIAS_TAG=""
  fi
}

if [[ -n "${INPUT_DOCKER_CUSTOM_TAG:-}" ]]; then
  TAG="${INPUT_DOCKER_CUSTOM_TAG}"
  LATEST="latest"
  PUSH="true"
  BUILD="${INPUT_DOCKER_DISABLE_RETAGGING:-false}"
elif [[ $GITHUB_REF == refs/heads/master ]]; then
  set_branch_tags master
  LATEST="master"
  PUSH="true"
elif [[ $GITHUB_REF == refs/heads/main ]]; then
  set_branch_tags main
  LATEST="main"
  PUSH="true"
elif [[ $GITHUB_REF == refs/heads/dev ]]; then
  set_branch_tags dev
  LATEST="dev"
  PUSH="true"
elif [[ $GITHUB_REF == refs/tags/v* ]]; then
  # By default the leading "v" is stripped (v1.2.3 -> 1.2.3). Set
  # INPUT_DOCKER_TAG_KEEP_V_PREFIX=true to keep it (v1.2.3 -> v1.2.3).
  if [[ "${INPUT_DOCKER_TAG_KEEP_V_PREFIX:-false}" == "true" ]]; then
    TAG="${GITHUB_REF#refs/tags/}"
  else
    TAG="${GITHUB_REF:11}"
  fi
  LATEST="latest"
  PUSH="true"
  BUILD="${INPUT_DOCKER_DISABLE_RETAGGING:-false}"
elif [[ $GITHUB_REF == refs/tags/* ]]; then
  TAG="${GITHUB_REF:10}"
  LATEST="latest"
  PUSH="true"
  BUILD="${INPUT_DOCKER_DISABLE_RETAGGING:-false}"
else
  TAG="${GITHUB_SHA::8}"
  PUSH="false"
  LATEST=""
fi

# TAG_LIST is the cross product of every configured registry (see
# lib/registries.sh) and every tag this build gets, so a single build-push
# invocation pushes to all of them at once.
TAG_LIST=""
for registry_entry in "${REGISTRIES[@]}"; do
  registry_ref="$(registry_field "$registry_entry" 1)/${INPUT_DOCKER_IMAGE}"
  [[ -n "$TAG_LIST" ]] && TAG_LIST+=","
  TAG_LIST+="${registry_ref}:${TAG}"
  if [[ -n "${ALIAS_TAG:-}" ]]; then
    TAG_LIST+=",${registry_ref}:${ALIAS_TAG}"
  fi
  if [[ -n "${LATEST:-}" ]]; then
    TAG_LIST+=",${registry_ref}:${LATEST}"
  fi
done

# GITOPS_TAG is the tag written to the external GitOps repo. It is always the
# non-timestamped tag: the stable <prefix>-<short-sha> alias for branch builds
# (ALIAS_TAG), and the plain TAG for release/custom builds (which have no
# timestamp anyway). Decoupling it from the timestamped image TAG avoids a
# mismatch when the action runs in separate invocations (e.g. build then push):
# each invocation recomputes a fresh timestamp for TAG, but the alias is
# deterministic, so the GitOps reference stays consistent and points at an image
# that was actually pushed.
GITOPS_TAG="${ALIAS_TAG:-$TAG}"

set_output "build" "$BUILD"
set_output "latest" "${LATEST:-}"
set_output "push" "$PUSH"
set_output "tag" "$TAG"
set_output "tag_list" "$TAG_LIST"
set_output "gitops_tag" "$GITOPS_TAG"
set_output "primary_registry" "$PRIMARY_REGISTRY"
set_output "primary_registry_api" "$PRIMARY_REGISTRY_API"
set_output "has_credentials" "$HAS_CREDENTIALS"
