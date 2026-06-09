#!/usr/bin/env bash
# Generates Docker image tags based on the current Git ref.
#
# Required env vars: GITHUB_REF, GITHUB_SHA, INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE
# Optional env vars: INPUT_DOCKER_CUSTOM_TAG, INPUT_DOCKER_DISABLE_RETAGGING,
#                    INPUT_DOCKER_TAG_TIMESTAMP, INPUT_DOCKER_TAG_KEEP_V_PREFIX
#
# Outputs (via GITHUB_OUTPUT): build, latest, push, tag, tag_list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env GITHUB_REF
require_env GITHUB_SHA
require_env INPUT_DOCKER_REGISTRY
require_env INPUT_DOCKER_IMAGE

BUILD="true"
# ALIAS_TAG is an additional immutable tag pushed alongside TAG (see set_branch_tags).
ALIAS_TAG=""

# set_branch_tags computes the immutable tag(s) for an environment branch and
# assigns them to the globals TAG and ALIAS_TAG.
#
# When INPUT_DOCKER_TAG_TIMESTAMP is "true" the canonical TAG gets a UTC timestamp
# inserted before the short SHA (e.g. dev-20260602143055-abcdef12). This makes
# branch tags sortable by Flux image automation (numerical policy) — the Git SHA
# alone is not orderable, so Flux cannot otherwise tell which build is newest.
# In that case ALIAS_TAG holds the legacy <prefix>-<short-sha> tag, which is also
# pushed: it is the stable per-commit handle that retag-image.sh looks up to find
# the source image for a release, so dropping it would break the release retag.
# The alias does not match Flux's "<prefix>-<digits>-<hex>" pattern, so Flux
# ignores it. When the flag is unset/false only the legacy <prefix>-<short-sha>
# tag is produced, so existing consumers are unaffected.
#
# The timestamp is overridable via BUILD_TIMESTAMP for deterministic tests.
set_branch_tags() {
  local prefix="$1"
  local sha="${GITHUB_SHA::8}"
  if [[ "${INPUT_DOCKER_TAG_TIMESTAMP:-false}" == "true" ]]; then
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

TAG_LIST="${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}:${TAG}"
if [[ -n "${ALIAS_TAG:-}" ]]; then
  TAG_LIST+=",${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}:${ALIAS_TAG}"
fi
if [[ -n "${LATEST:-}" ]]; then
  TAG_LIST+=",${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}:${LATEST}"
fi

set_output "build" "$BUILD"
set_output "latest" "${LATEST:-}"
set_output "push" "$PUSH"
set_output "tag" "$TAG"
set_output "tag_list" "$TAG_LIST"
