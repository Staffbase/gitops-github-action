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

if [[ -n "${INPUT_DOCKER_CUSTOM_TAG:-}" ]]; then
  TAG="${INPUT_DOCKER_CUSTOM_TAG}"
  LATEST="latest"
  PUSH="true"
  BUILD="${INPUT_DOCKER_DISABLE_RETAGGING:-false}"
elif [[ $GITHUB_REF == refs/heads/master ]]; then
  TAG="master-${GITHUB_SHA::8}"
  LATEST="master"
  PUSH="true"
elif [[ $GITHUB_REF == refs/heads/main ]]; then
  TAG="main-${GITHUB_SHA::8}"
  LATEST="main"
  PUSH="true"
elif [[ $GITHUB_REF == refs/heads/dev ]]; then
  TAG="dev-${GITHUB_SHA::8}"
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
