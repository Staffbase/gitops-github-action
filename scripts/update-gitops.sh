#!/usr/bin/env bash
# Updates Docker image references in a GitOps repository.
# Determines which environment (DEV/STAGE/PROD) to update based on the Git ref,
# then updates the corresponding YAML files using yq.
#
# Required env vars: GITHUB_REF, GITHUB_SHA, GITHUB_REPOSITORY,
#   INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE, INPUT_TAG, INPUT_PUSH,
#   INPUT_CREATE_DEPLOYMENT, INPUT_GITOPS_USER, INPUT_GITOPS_EMAIL,
#   INPUT_GITOPS_TOKEN, INPUT_GITOPS_ORGANIZATION, INPUT_GITOPS_REPOSITORY
# Optional env vars: INPUT_GITOPS_DEV, INPUT_GITOPS_STAGE, INPUT_GITOPS_PROD,
#   INPUT_DEPLOYMENT_IDS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/gitops-functions.sh
source "${SCRIPT_DIR}/lib/gitops-functions.sh"

require_env GITHUB_REF
require_env INPUT_DOCKER_REGISTRY
require_env INPUT_DOCKER_IMAGE
require_env INPUT_TAG
require_env INPUT_GITOPS_USER
require_env INPUT_GITOPS_EMAIL
require_env INPUT_GITOPS_TOKEN
require_env INPUT_GITOPS_ORGANIZATION
require_env INPUT_GITOPS_REPOSITORY

# Used by gitops-functions.sh (process_file_updates -> update_file)
# shellcheck disable=SC2034
IMAGE="${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}:${INPUT_TAG}"

# Configure git user
git config --global user.email "${INPUT_GITOPS_EMAIL}" && git config --global user.name "${INPUT_GITOPS_USER}"

if [[ ( $GITHUB_REF == refs/heads/master || $GITHUB_REF == refs/heads/main ) && -n "${INPUT_GITOPS_STAGE:-}" ]]; then
  log_info "Run update for STAGE"
  process_file_updates "$INPUT_GITOPS_STAGE" "true"

elif [[ $GITHUB_REF == refs/heads/dev && -n "${INPUT_GITOPS_DEV:-}" ]]; then
  log_info "Run update for DEV"
  process_file_updates "$INPUT_GITOPS_DEV" "true"

elif [[ $GITHUB_REF == refs/tags/* && -n "${INPUT_GITOPS_PROD:-}" ]]; then
  log_info "Run update for PROD"
  process_file_updates "$INPUT_GITOPS_PROD" "true"

elif [[ -n "${INPUT_GITOPS_DEV:-}" ]]; then
  log_info "Simulate update for DEV"
  process_file_updates "$INPUT_GITOPS_DEV" "false"
fi
