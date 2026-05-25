#!/usr/bin/env bash
# Updates Docker image references in a GitOps repository.
# Determines which environment (DEV/STAGE/PROD) to update based on the Git ref,
# then updates the corresponding YAML files using yq.
#
# Required env vars: GITHUB_REF, GITHUB_SHA, GITHUB_REPOSITORY,
#   INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE, INPUT_TAG, INPUT_PUSH,
#   INPUT_GITOPS_USER, INPUT_GITOPS_EMAIL,
#   INPUT_GITOPS_TOKEN, INPUT_GITOPS_ORGANIZATION, INPUT_GITOPS_REPOSITORY
# Optional env vars: INPUT_GITOPS_UPDATES (preferred, applies to all envs),
#   INPUT_GITOPS_DEV, INPUT_GITOPS_STAGE, INPUT_GITOPS_PROD (legacy, per-env overrides),
#   INPUT_GITOPS_NAMESPACE (required when using shorthand path format)

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

NAMESPACE="${INPUT_GITOPS_NAMESPACE:-}"

# Configure git user
git config --global user.email "${INPUT_GITOPS_EMAIL}" && git config --global user.name "${INPUT_GITOPS_USER}"

# Derive environment and commit flag from git ref
env=""
should_commit="true"
if [[ $GITHUB_REF == refs/heads/master || $GITHUB_REF == refs/heads/main ]]; then
  env="stage"
elif [[ $GITHUB_REF == refs/heads/dev ]]; then
  env="dev"
elif [[ $GITHUB_REF == refs/tags/* ]]; then
  env="prod"
else
  env="dev"
  should_commit="false"
fi

# Resolve file list: gitops-updates takes precedence over per-env inputs
file_list=""
if [[ -n "${INPUT_GITOPS_UPDATES:-}" ]]; then
  file_list="$INPUT_GITOPS_UPDATES"
else
  case "$env" in
    stage) file_list="${INPUT_GITOPS_STAGE:-}" ;;
    dev)   file_list="${INPUT_GITOPS_DEV:-}" ;;
    prod)  file_list="${INPUT_GITOPS_PROD:-}" ;;
  esac
fi

if [[ -n "$file_list" ]]; then
  if [[ "$should_commit" == "true" ]]; then
    log_info "Run update for ${env^^}"
  else
    log_info "Simulate update for ${env^^}"
  fi
  process_file_updates "$(expand_with_regions "$file_list" "$env" "$NAMESPACE")" "$should_commit"
fi
