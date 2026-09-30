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
declare -A seen_username seen_password
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

  # Docker's credential store is keyed by host alone, so two entries sharing
  # a host but carrying different credentials would silently overwrite each
  # other — whichever logs in last wins for every entry on that host.
  if [[ -n "${seen_username[$host]+set}" ]]; then
    if [[ "${seen_username[$host]}" != "$username" || "${seen_password[$host]}" != "$password" ]]; then
      log_error "Multiple docker-registries entries use host '${host}' with different credentials. Docker's credential store is keyed by host, so only one set of credentials can be active for it — use the same credentials for every entry on that host."
      exit 1
    fi
    log_info "Skipping login for '${registry}': already logged in to '${host}'."
    continue
  fi
  seen_username[$host]="$username"
  seen_password[$host]="$password"

  echo "Logging in to ${host}"
  echo "$password" | docker login "$host" --username "$username" --password-stdin
done
