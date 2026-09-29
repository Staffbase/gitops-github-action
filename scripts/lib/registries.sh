#!/usr/bin/env bash
# Resolves the set of registries to log into and push to.
# Sourced by other scripts — not executed directly.
#
# INPUT_DOCKER_REGISTRIES is a newline-separated list of
# "registry[|username[|password]]" entries. The first entry is the primary
# registry — the one used for GitOps manifest updates and release-retag
# lookups. A missing username/password on a line falls back to the global
# INPUT_DOCKER_USERNAME/INPUT_DOCKER_PASSWORD.
#
# action.yml declares docker-registries as its only registry input (default
# 'registry.staffbase.com'), so INPUT_DOCKER_REGISTRIES is always populated —
# callers only ever deal with this one variable.
#
# Required env vars: INPUT_DOCKER_REGISTRIES
# Optional env vars: INPUT_DOCKER_USERNAME, INPUT_DOCKER_PASSWORD

# resolve_registries populates the global array REGISTRIES with one
# "registry<TAB>username<TAB>password" entry per registry.
resolve_registries() {
  REGISTRIES=()
  local line registry rest username password

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    registry="${line%%|*}"
    rest="${line#"$registry"}"
    rest="${rest#|}"
    username="${rest%%|*}"
    password="${rest#"$username"}"
    password="${password#|}"
    REGISTRIES+=("${registry}"$'\t'"${username:-${INPUT_DOCKER_USERNAME:-}}"$'\t'"${password:-${INPUT_DOCKER_PASSWORD:-}}")
  done <<< "${INPUT_DOCKER_REGISTRIES}"
}

# registry_field extracts one column (1=registry, 2=username, 3=password) from
# a REGISTRIES entry.
registry_field() {
  local entry="$1" field="$2"
  cut -f "$field" <<< "$entry"
}
