#!/usr/bin/env bash
# Logs Docker into every configured registry (see lib/registries.sh). Entries
# missing a username or password are skipped — e.g. when the action is used
# purely to update the GitOps repository without touching any registry.
#
# Required env vars: INPUT_DOCKER_REGISTRIES
# Optional env vars: INPUT_DOCKER_USERNAME, INPUT_DOCKER_PASSWORD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/registries.sh
source "${SCRIPT_DIR}/lib/registries.sh"

require_env INPUT_DOCKER_REGISTRIES
require_tool docker

resolve_registries
for entry in "${REGISTRIES[@]}"; do
  registry="$(registry_field "$entry" 1)"
  username="$(registry_field "$entry" 2)"
  password="$(registry_field "$entry" 3)"

  if [[ -z "$username" || -z "$password" ]]; then
    log_info "Skipping login for '${registry}': no credentials configured."
    continue
  fi

  # A registry entry may carry a path prefix after the host (e.g. GAR's
  # project/repository, baked in so it ends up in the pushed image ref).
  # `docker login` only accepts the host.
  host="${registry%%/*}"
  echo "Logging in to ${host}"
  echo "$password" | docker login "$host" --username "$username" --password-stdin
done
