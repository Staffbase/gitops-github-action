#!/usr/bin/env bash
# GitOps helper functions for updating Kubernetes manifests.
# Sourced by update-gitops.sh — not executed directly.
#
# Expected env vars (set by caller):
#   INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE, INPUT_TAG, INPUT_PUSH,
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

update_file() {
  local file="$1"
  local field="$2"
  local image="$3"

  echo "Check if path ${file} ${field} exists and get old current version"
  yq -e ."${field}" "${file}"
  echo "Run update ${file} ${field} ${image}"
  yq -i ."${field}"=\""${image}"\" "${file}"

  echo "Writing deployment annotations to ${file}"
  yq -i '.metadata.annotations["deploy.staffbase.com/repositoryFullName"] = "'"${GITHUB_REPOSITORY}"'"' "${file}"
  yq -i '.metadata.annotations["deploy.staffbase.com/commitSha"] = "'"${GITHUB_SHA}"'"' "${file}"
  yq -i '.metadata.annotations["deploy.staffbase.com/version"] = "'"${INPUT_TAG}"'"' "${file}"
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
