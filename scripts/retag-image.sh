#!/usr/bin/env bash
# Retags an existing Docker image in the registry without rebuilding.
# Polls for an existing master-/main- tagged image on the primary registry and
# retags it with the release tag, then replicates that tag onto every
# additional registry (see lib/registries.sh) via `docker buildx imagetools
# create` — unlike the raw manifest API below, that works regardless of the
# target registry's auth scheme (basic auth, OAuth2 bearer token, ...), since
# it reuses whatever `docker login` already set up.
#
# Required env vars: GITHUB_SHA, INPUT_DOCKER_REGISTRIES,
#                    INPUT_DOCKER_REGISTRY_API, INPUT_DOCKER_IMAGE, INPUT_TAG,
#                    INPUT_LATEST
# Optional env vars: INPUT_DOCKER_USERNAME, INPUT_DOCKER_PASSWORD,
#                    INPUT_RETAG_DIGEST (sha256:<64 hex>; retag exactly this
#                    manifest instead of resolving the master-/main- tag),
#                    RETAG_TIMEOUT_SECONDS (default: 300),
#                    RETAG_POLL_INTERVAL (default: 10)
#
# Outputs (via GITHUB_OUTPUT): digest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/registries.sh
source "${SCRIPT_DIR}/lib/registries.sh"

require_env GITHUB_SHA
require_env INPUT_DOCKER_REGISTRIES
require_env INPUT_DOCKER_REGISTRY_API
require_env INPUT_DOCKER_IMAGE
require_env INPUT_TAG
require_env INPUT_LATEST

# The manifest API talks to the primary registry (INPUT_DOCKER_REGISTRY_API),
# so it authenticates with the primary entry's own resolved credentials, not
# the raw top-level ones — a registry can supply its credentials entirely
# inline in INPUT_DOCKER_REGISTRIES (e.g. GAR's oauth2accesstoken).
resolve_registries
PRIMARY_USERNAME="$(registry_field "${REGISTRIES[0]}" 2)"
PRIMARY_PASSWORD="$(registry_field "${REGISTRIES[0]}" 3)"
if [[ -z "$PRIMARY_USERNAME" || -z "$PRIMARY_PASSWORD" ]]; then
  log_error "No credentials configured for the primary registry ($(registry_field "${REGISTRIES[0]}" 1))"
  exit 1
fi

# "oauth2accesstoken" is the fixed username Google Artifact/Container Registry
# uses to mean "the password is actually an OAuth2 access token" — the same
# convention `docker login`/`gcloud auth configure-docker` use. Their raw
# registry API only accepts that token as a Bearer header, unlike Harbor's
# manifest endpoints, which accept HTTP Basic directly.
if [[ "$PRIMARY_USERNAME" == "oauth2accesstoken" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${PRIMARY_PASSWORD}")
else
  AUTH_ARGS=(-u "${PRIMARY_USERNAME}:${PRIMARY_PASSWORD}")
fi

TIMEOUT="${RETAG_TIMEOUT_SECONDS:-300}"
POLL_INTERVAL="${RETAG_POLL_INTERVAL:-10}"

CHECK_EXISTING_TAGS="master-${GITHUB_SHA::8} main-${GITHUB_SHA::8}"
RETAG_DIGEST="${INPUT_RETAG_DIGEST:-}"
if [[ -n "$RETAG_DIGEST" ]]; then
  if [[ ! "$RETAG_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    log_error "INPUT_RETAG_DIGEST must be sha256:<64 lowercase hex characters>"
    exit 1
  fi
  command -v sha256sum &>/dev/null || require_tool shasum
  # A caller that verified a digest gets exactly that manifest; a tag could be moved after verification.
  CHECK_EXISTING_TAGS="$RETAG_DIGEST"
fi
ACCEPT_HEADER="application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json"

echo "CHECK_EXISTING_TAGS: ${CHECK_EXISTING_TAGS}"
echo "Check if an image already exists for ${INPUT_DOCKER_IMAGE} (${CHECK_EXISTING_TAGS// /, })"

# The manifest is kept in a file and uploaded with --data-binary so its bytes,
# and therefore its digest, stay exactly as fetched.
MANIFEST_FILE="$(mktemp)"
trap 'rm -f "$MANIFEST_FILE"' EXIT

sha256_file() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

retag_manifest() {
  local target_tag="$1"
  local content_type="$2"
  local digest_args=()
  [[ -z "$RETAG_DIGEST" ]] || digest_args=(-D put-headers.txt)
  curl --fail-with-body -X PUT \
    -H "Content-Type: ${content_type}" \
    "${AUTH_ARGS[@]}" \
    ${digest_args[@]+"${digest_args[@]}"} \
    --data-binary "@${MANIFEST_FILE}" \
    "${INPUT_DOCKER_REGISTRY_API}${INPUT_DOCKER_IMAGE}/manifests/${target_tag}"
  if [[ -n "$RETAG_DIGEST" ]]; then
    local stored
    stored=$(grep -i "^Docker-Content-Digest:" put-headers.txt | cut -d' ' -f2 | tr -d '\r' || true)
    if [[ "$stored" != "$RETAG_DIGEST" ]]; then
      log_error "${INPUT_DOCKER_IMAGE}:${target_tag} was stored as ${stored:-an unknown digest}, not ${RETAG_DIGEST}"
      exit 1
    fi
  fi
}

foundImage=false
DETECTED_CONTENT_TYPE=""
DIGEST=""

end=$((SECONDS + TIMEOUT))
attempt=1
while [ $SECONDS -lt $end ]; do
  remaining=$((end - SECONDS))
  echo "Poll attempt ${attempt} (${remaining}s remaining)..."

  for tag in $CHECK_EXISTING_TAGS; do
    : > "$MANIFEST_FILE"
    curl -s -D headers.txt -o "$MANIFEST_FILE" \
      -H "Accept: ${ACCEPT_HEADER}" \
      "${AUTH_ARGS[@]}" \
      "${INPUT_DOCKER_REGISTRY_API}${INPUT_DOCKER_IMAGE}/manifests/${tag}"

    if grep -q "errors" "$MANIFEST_FILE"; then
      echo "No image found for ${INPUT_DOCKER_IMAGE}:${tag}"
      continue
    else
      echo "Image found for ${INPUT_DOCKER_IMAGE}:${tag}"
      foundImage=true
      DETECTED_CONTENT_TYPE=$(grep -i "^Content-Type:" headers.txt | cut -d' ' -f2 | tr -d '\r')
      DIGEST=$(grep -i "^Docker-Content-Digest:" headers.txt | cut -d' ' -f2 | tr -d '\r')
      if [[ -n "$RETAG_DIGEST" && "$DIGEST" != "$RETAG_DIGEST" ]]; then
        log_error "The registry returned ${DIGEST:-no digest} for ${INPUT_DOCKER_IMAGE}@${RETAG_DIGEST}"
        exit 1
      fi
      if [[ -n "$RETAG_DIGEST" && "sha256:$(sha256_file "$MANIFEST_FILE")" != "$RETAG_DIGEST" ]]; then
        log_error "The manifest bytes fetched for ${INPUT_DOCKER_IMAGE}@${RETAG_DIGEST} do not match that digest"
        exit 1
      fi
      break 2
    fi
  done

  sleep "$POLL_INTERVAL"
  attempt=$((attempt + 1))
done

if [[ $foundImage == false ]]; then
  log_error "No image found for ${INPUT_DOCKER_IMAGE} (${CHECK_EXISTING_TAGS// /, }) within ${TIMEOUT} seconds"
  exit 1
fi

echo "Retagging image with release version and :latest tags for ${INPUT_DOCKER_IMAGE}"
echo "Using Content-Type: ${DETECTED_CONTENT_TYPE}"

retag_manifest "$INPUT_TAG" "$DETECTED_CONTENT_TYPE"
retag_manifest "$INPUT_LATEST" "$DETECTED_CONTENT_TYPE"

if [[ ${#REGISTRIES[@]} -gt 1 ]]; then
  require_tool docker
  PRIMARY_REGISTRY="$(registry_field "${REGISTRIES[0]}" 1)"
  SOURCE_REF="${PRIMARY_REGISTRY}/${INPUT_DOCKER_IMAGE}@${DIGEST}"
  for entry in "${REGISTRIES[@]:1}"; do
    registry="$(registry_field "$entry" 1)"
    echo "Replicating ${INPUT_DOCKER_IMAGE}:${INPUT_TAG} to ${registry}"
    docker buildx imagetools create \
      --tag "${registry}/${INPUT_DOCKER_IMAGE}:${INPUT_TAG}" \
      --tag "${registry}/${INPUT_DOCKER_IMAGE}:${INPUT_LATEST}" \
      "$SOURCE_REF"
  done
fi

set_output "digest" "$DIGEST"
