#!/usr/bin/env bash
# GitOps helper functions for updating Kubernetes manifests.
# Sourced by update-gitops.sh — not executed directly.
#
# Expected env vars (set by caller):
#   INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE, INPUT_TAG, INPUT_PUSH,
#   INPUT_CREATE_DEPLOYMENT, INPUT_DEPLOYMENT_IDS,
#   INPUT_GITOPS_USER, INPUT_GITOPS_TOKEN,
#   INPUT_GITOPS_ORGANIZATION, INPUT_GITOPS_REPOSITORY,
#   GITHUB_REPOSITORY, GITHUB_SHA, IMAGE

push_to_gitops_repo() {
  git pull --rebase "https://${INPUT_GITOPS_USER}:${INPUT_GITOPS_TOKEN}@github.com/${INPUT_GITOPS_ORGANIZATION}/${INPUT_GITOPS_REPOSITORY}.git"
  git push "https://${INPUT_GITOPS_USER}:${INPUT_GITOPS_TOKEN}@github.com/${INPUT_GITOPS_ORGANIZATION}/${INPUT_GITOPS_REPOSITORY}.git"
}

commit_changes() {
  if [[ "${INPUT_PUSH}" == "true" ]]; then
    git add .

    if git diff-index --quiet HEAD; then
      echo "There were no changes..."
      return
    fi

    git commit -m "Release ${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}:${INPUT_TAG}"

    retry_with_backoff 5 2 push_to_gitops_repo
  fi
}

# Derives the environment identifier from a mops file path.
# Expected path format: kubernetes/namespaces/<service>/<env>/<cluster>/<file>.yaml
derive_environment() {
  local file_path="$1"
  local env cluster
  env=$(echo "$file_path" | cut -d'/' -f4)
  cluster=$(echo "$file_path" | cut -d'/' -f5)
  echo "${env}-${cluster}"
}

update_file() {
  local file="$1"
  local field="$2"
  local image="$3"

  echo "Check if path ${file} ${field} exists and get old current version"
  yq -e ."${field}" "${file}"
  echo "Run update ${file} ${field} ${image}"
  yq -i ."${field}"=\""${image}"\" "${file}"

  if [[ "${INPUT_CREATE_DEPLOYMENT}" == "true" ]]; then
    local deploy_env
    deploy_env=$(derive_environment "${file}")

    echo "Writing deployment annotations to ${file}"
    yq -i '.metadata.annotations["deploy.staffbase.com/repo"] = "'"${GITHUB_REPOSITORY}"'"' "${file}"
    yq -i '.metadata.annotations["deploy.staffbase.com/sha"] = "'"${GITHUB_SHA}"'"' "${file}"

    # Write deployment-id annotation if available from the create_deployments step
    local deploy_id=""
    if [[ -n "${INPUT_DEPLOYMENT_IDS:-}" && "${INPUT_DEPLOYMENT_IDS}" != "{}" ]]; then
      deploy_id=$(echo "${INPUT_DEPLOYMENT_IDS}" | jq -r --arg env "$deploy_env" '.[$env] // empty')
    fi

    if [[ -n "$deploy_id" ]]; then
      yq -i '.metadata.annotations["deploy.staffbase.com/deployment-id"] = "'"${deploy_id}"'"' "${file}"
    fi
  fi
}

process_file_updates() {
  local file_list="$1"
  local should_commit="$2"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local file field
    read -r file field <<< "$line"
    update_file "$file" "$field" "$IMAGE"
  done <<< "$file_list"

  if [[ "$should_commit" == "true" ]]; then
    commit_changes
  fi
}
