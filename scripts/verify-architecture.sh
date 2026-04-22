#!/usr/bin/env bash
# Verifies that the runner CPU architecture matches the requested build platforms.
# Prevents emulation-based builds which are slow and unreliable.
#
# Required env vars: RUNNER_ARCH, INPUT_DOCKER_BUILD_PLATFORMS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env RUNNER_ARCH
require_env INPUT_DOCKER_BUILD_PLATFORMS

echo "Runner CPU Architecture: $RUNNER_ARCH"
echo "Requested Build Platforms: $INPUT_DOCKER_BUILD_PLATFORMS"

if [[ "$RUNNER_ARCH" == "X64" ]]; then
  if [[ "$INPUT_DOCKER_BUILD_PLATFORMS" == *"linux/arm64"* ]]; then
    log_error "Runner is X64 (Intel/AMD) but build includes 'linux/arm64'. This requires emulation. Aborting strictly."
    exit 1
  fi
fi

if [[ "$RUNNER_ARCH" == "ARM64" ]]; then
  if [[ "$INPUT_DOCKER_BUILD_PLATFORMS" == *"linux/amd64"* ]]; then
    log_error "Runner is ARM64 (Apple Silicon/Graviton) but build includes 'linux/amd64'. This requires emulation. Aborting strictly."
    exit 1
  fi
fi

echo "Architecture match verified for native build"
