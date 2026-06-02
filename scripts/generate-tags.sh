#!/usr/bin/env bash
# Generates Docker image tags based on the current Git ref.
#
# Required env vars: GITHUB_REF, GITHUB_SHA, INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE
# Optional env vars: INPUT_DOCKER_CUSTOM_TAG, INPUT_DOCKER_DISABLE_RETAGGING
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

# branch_tag builds the immutable tag for an environment branch.
#
# When INPUT_DOCKER_TAG_TIMESTAMP is "true" the tag gets a UTC timestamp inserted
# before the short SHA (e.g. dev-20260602143055-abcdef12). This makes branch tags
# sortable by Flux image automation (numerical policy) — the git SHA alone is not
# orderable, so Flux cannot otherwise tell which build is newest. The SHA is kept
# for traceability. When the flag is unset/false the legacy <prefix>-<sha> shape
# is produced, so existing consumers are unaffected.
#
# The timestamp is overridable via BUILD_TIMESTAMP for deterministic tests.
branch_tag() {
  local prefix="$1"
  if [[ "${INPUT_DOCKER_TAG_TIMESTAMP:-false}" == "true" ]]; then
    local ts="${BUILD_TIMESTAMP:-$(date -u +%Y%m%d%H%M%S)}"
    echo "${prefix}-${ts}-${GITHUB_SHA::8}"
  else
    echo "${prefix}-${GITHUB_SHA::8}"
  fi
}

if [[ -n "${INPUT_DOCKER_CUSTOM_TAG:-}" ]]; then
  TAG="${INPUT_DOCKER_CUSTOM_TAG}"
  LATEST="latest"
  PUSH="true"
  BUILD="${INPUT_DOCKER_DISABLE_RETAGGING:-false}"
elif [[ $GITHUB_REF == refs/heads/master ]]; then
  TAG="$(branch_tag master)"
  LATEST="master"
  PUSH="true"
elif [[ $GITHUB_REF == refs/heads/main ]]; then
  TAG="$(branch_tag main)"
  LATEST="main"
  PUSH="true"
elif [[ $GITHUB_REF == refs/heads/dev ]]; then
  TAG="$(branch_tag dev)"
  LATEST="dev"
  PUSH="true"
elif [[ $GITHUB_REF == refs/tags/v* ]]; then
  TAG="${GITHUB_REF:11}"
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
if [[ -n "${LATEST:-}" ]]; then
  TAG_LIST+=",${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}:${LATEST}"
fi

set_output "build" "$BUILD"
set_output "latest" "${LATEST:-}"
set_output "push" "$PUSH"
set_output "tag" "$TAG"
set_output "tag_list" "$TAG_LIST"
