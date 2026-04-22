#!/usr/bin/env bash
# Retags an existing Docker image in the registry without rebuilding.
# Polls for an existing master-/main- tagged image and retags it with the release tag.
#
# Required env vars: GITHUB_SHA, INPUT_DOCKER_USERNAME, INPUT_DOCKER_PASSWORD,
#                    INPUT_DOCKER_REGISTRY_API, INPUT_DOCKER_IMAGE, INPUT_TAG, INPUT_LATEST
# Optional env vars: RETAG_TIMEOUT_SECONDS (default: 300), RETAG_POLL_INTERVAL (default: 10)
#
# Outputs (via GITHUB_OUTPUT): digest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env GITHUB_SHA
require_env INPUT_DOCKER_USERNAME
require_env INPUT_DOCKER_PASSWORD
require_env INPUT_DOCKER_REGISTRY_API
require_env INPUT_DOCKER_IMAGE
require_env INPUT_TAG
require_env INPUT_LATEST

TIMEOUT="${RETAG_TIMEOUT_SECONDS:-300}"
POLL_INTERVAL="${RETAG_POLL_INTERVAL:-10}"

CHECK_EXISTING_TAGS="master-${GITHUB_SHA::8} main-${GITHUB_SHA::8}"
ACCEPT_HEADER="application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json"

echo "CHECK_EXISTING_TAGS: ${CHECK_EXISTING_TAGS}"
echo "Check if an image already exists for ${INPUT_DOCKER_IMAGE}:main|master-${GITHUB_SHA::8}"

retag_manifest() {
  local target_tag="$1"
  local manifest="$2"
  local content_type="$3"
  curl --fail-with-body -X PUT \
    -H "Content-Type: ${content_type}" \
    -u "${INPUT_DOCKER_USERNAME}:${INPUT_DOCKER_PASSWORD}" \
    -d "${manifest}" \
    "${INPUT_DOCKER_REGISTRY_API}${INPUT_DOCKER_IMAGE}/manifests/${target_tag}"
}

foundImage=false
DETECTED_CONTENT_TYPE=""
DIGEST=""
MANIFEST=""

end=$((SECONDS + TIMEOUT))
attempt=1
while [ $SECONDS -lt $end ]; do
  remaining=$((end - SECONDS))
  echo "Poll attempt ${attempt} (${remaining}s remaining)..."

  for tag in $CHECK_EXISTING_TAGS; do
    MANIFEST=$(curl -s -D headers.txt \
      -H "Accept: ${ACCEPT_HEADER}" \
      -u "${INPUT_DOCKER_USERNAME}:${INPUT_DOCKER_PASSWORD}" \
      "${INPUT_DOCKER_REGISTRY_API}${INPUT_DOCKER_IMAGE}/manifests/${tag}")

    if [[ $MANIFEST == *"errors"* ]]; then
      echo "No image found for ${INPUT_DOCKER_IMAGE}:${tag}"
      continue
    else
      echo "Image found for ${INPUT_DOCKER_IMAGE}:${tag}"
      foundImage=true
      DETECTED_CONTENT_TYPE=$(grep -i "^Content-Type:" headers.txt | cut -d' ' -f2 | tr -d '\r')
      DIGEST=$(grep -i "^Docker-Content-Digest:" headers.txt | cut -d' ' -f2 | tr -d '\r')
      break 2
    fi
  done

  sleep "$POLL_INTERVAL"
  attempt=$((attempt + 1))
done

if [[ $foundImage == false ]]; then
  log_error "No image found for ${INPUT_DOCKER_IMAGE}:main|master-${GITHUB_SHA::8} within ${TIMEOUT} seconds"
  exit 1
fi

echo "Retagging image with release version and :latest tags for ${INPUT_DOCKER_IMAGE}"
echo "Using Content-Type: ${DETECTED_CONTENT_TYPE}"

retag_manifest "$INPUT_TAG" "$MANIFEST" "$DETECTED_CONTENT_TYPE"
retag_manifest "$INPUT_LATEST" "$MANIFEST" "$DETECTED_CONTENT_TYPE"

set_output "digest" "$DIGEST"
