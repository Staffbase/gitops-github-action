#!/usr/bin/env bash
# Resolves platforms, tags and buildx outputs for the Docker build step.
#
# With multiarch-mode unset this is a pass-through of the caller's inputs, so the
# single-arch behaviour is unchanged. With multiarch-mode="build" the runner's own
# architecture decides the platform (never emulation) and the image is pushed by
# digest only — the tags are applied later by merge-manifests.sh on the merge job.
#
# Required env vars: RUNNER_ARCH
# Optional env vars: INPUT_MULTIARCH_MODE, INPUT_DOCKER_BUILD_PLATFORMS,
#                    INPUT_DOCKER_BUILD_OUTPUTS, INPUT_TAG_LIST, INPUT_PUSH,
#                    INPUT_DOCKER_REGISTRY, INPUT_DOCKER_IMAGE
#
# Outputs (via GITHUB_OUTPUT): arch, platforms, tags, build_outputs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODE="${INPUT_MULTIARCH_MODE:-}"
PLATFORMS="${INPUT_DOCKER_BUILD_PLATFORMS:-}"
TAGS="${INPUT_TAG_LIST:-}"
BUILD_OUTPUTS="${INPUT_DOCKER_BUILD_OUTPUTS:-}"

if [[ "$MODE" != "" && "$MODE" != "build" && "$MODE" != "merge" ]]; then
  log_error "Invalid multiarch-mode '${MODE}'. Expected '', 'build' or 'merge'."
  exit 1
fi

ARCH=""
case "${RUNNER_ARCH:-}" in
  X64) ARCH="amd64" ;;
  ARM64) ARCH="arm64" ;;
esac

if [[ "$MODE" == "build" ]]; then
  if [[ -z "$ARCH" ]]; then
    log_error "Unsupported runner architecture '${RUNNER_ARCH:-}' for multiarch-mode 'build'. Expected X64 or ARM64."
    exit 1
  fi
  if [[ -n "$BUILD_OUTPUTS" ]]; then
    log_error "docker-build-outputs cannot be combined with multiarch-mode 'build' (the build pushes by digest)."
    exit 1
  fi
  require_env INPUT_DOCKER_REGISTRY
  require_env INPUT_DOCKER_IMAGE

  PLATFORMS="linux/${ARCH}"

  # Without a push (e.g. feature branches) there is nothing to merge later, so
  # keep the plain build and let the tags apply as usual.
  if [[ "${INPUT_PUSH:-}" == "true" ]]; then
    TAGS=""
    BUILD_OUTPUTS="type=image,name=${INPUT_DOCKER_REGISTRY}/${INPUT_DOCKER_IMAGE},push-by-digest=true,name-canonical=true,push=true"
  fi
fi

echo "Build platforms: ${PLATFORMS}"

# CACHE_SUFFIX is appended verbatim to the type=gha cache refs. The parallel
# matrix jobs must not share one cache scope, or they keep overwriting each
# other's manifest. Empty outside build mode to keep the default scope.
CACHE_SUFFIX=""
if [[ "$MODE" == "build" ]]; then
  CACHE_SUFFIX=",scope=${ARCH}"
fi

set_output "arch" "$ARCH"
set_output "cache_suffix" "$CACHE_SUFFIX"
set_output "platforms" "$PLATFORMS"
set_output "tags" "$TAGS"
set_output "build_outputs" "$BUILD_OUTPUTS"
