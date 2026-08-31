#!/usr/bin/env bash
# Combines the per-architecture images pushed by the matrix build jobs into a
# single multi-arch manifest list and applies the real tags to it.
#
# Each build job pushed its image by digest only and uploaded an empty file named
# after that digest. This script turns those digests into one image index.
#
# Required env vars: INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE, INPUT_TAG_LIST,
#                    INPUT_DIGESTS_PATH
#
# Outputs (via GITHUB_OUTPUT): digest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env INPUT_DOCKER_REGISTRY
require_env INPUT_DOCKER_IMAGE
require_env INPUT_TAG_LIST
require_env INPUT_DIGESTS_PATH
require_tool docker
require_tool jq

IMAGE="${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE}"

sources=()
while IFS= read -r digest; do
  sources+=("${IMAGE}@sha256:${digest}")
done < <(find "$INPUT_DIGESTS_PATH" -type f -exec basename {} \; | grep -E '^[0-9a-f]{64}$' | sort)

if [[ ${#sources[@]} -eq 0 ]]; then
  log_error "No digests found in '${INPUT_DIGESTS_PATH}'. Did the multiarch build jobs run and upload their digests?"
  exit 1
fi

tag_args=()
IFS=',' read -ra tags <<< "$INPUT_TAG_LIST"
for tag in "${tags[@]}"; do
  [[ -n "$tag" ]] && tag_args+=("--tag" "$tag")
done

echo "Merging ${#sources[@]} image(s) into ${#tag_args[@]} tag(s)"
docker buildx imagetools create "${tag_args[@]}" "${sources[@]}"

DIGEST="$(docker buildx imagetools inspect "${tags[0]}" --format '{{json .Manifest}}' | jq -r '.digest')"
echo "Multi-arch image digest: ${DIGEST}"

set_output "digest" "$DIGEST"
