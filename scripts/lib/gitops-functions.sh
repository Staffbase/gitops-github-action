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

expand_with_regions() {
  local file_list="$1"
  local env="$2"
  local namespace="$3"
  local expanded=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Without a namespace, pass every line through unchanged (legacy / external repos)
    if [[ -z "$namespace" ]]; then
      expanded+="${line}"$'\n'
      continue
    fi

    # With a namespace set, explicit full paths (starting with kubernetes/) pass through unchanged
    if [[ "$line" == kubernetes/* ]]; then
      expanded+="${line}"$'\n'
      continue
    fi

    local filename field_token resolved_field
    read -r filename field_token <<< "$line"

    if [[ -z "$field_token" ]]; then
      resolved_field="spec.template.spec.containers.${namespace}.image"
    elif [[ "$field_token" != *.* ]]; then
      resolved_field="spec.template.spec.containers.${field_token}.image"
    else
      resolved_field="$field_token"
    fi

    local regions_dir="kubernetes/namespaces/${namespace}/${env}"
    if [[ -d "$regions_dir" ]]; then
      for region_dir in "${regions_dir}"/*/; do
        [[ -d "$region_dir" ]] || continue
        local region="${region_dir%/}"
        region="${region##*/}"
        expanded+="${regions_dir}/${region}/${filename} ${resolved_field}"$'\n'
      done
    else
      log_warn "Auto-discovery: directory ${regions_dir} not found, skipping"
    fi
  done <<< "$file_list"

  printf '%s' "$expanded"
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
