#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/resolve-build-config.sh"

setup() {
  setup_common
  export RUNNER_ARCH="X64"
  export INPUT_DOCKER_REGISTRY="registry.example.com"
  export INPUT_DOCKER_IMAGE="private/my-service"
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/amd64"
  export INPUT_TAG_LIST="registry.example.com/private/my-service:dev-abcdef12"
  export INPUT_PUSH="true"
}

teardown() {
  teardown_common
}

# --- default (single-arch) mode is a pass-through ---

@test "default mode passes inputs through unchanged" {
  run "$SCRIPT"
  assert_success
  assert_output_value "platforms" "linux/amd64"
  assert_output_value "tags" "registry.example.com/private/my-service:dev-abcdef12"
  assert_output_value "build_outputs" ""
  assert_output_value "cache_suffix" ""
}

@test "default mode keeps custom docker-build-outputs" {
  export INPUT_DOCKER_BUILD_OUTPUTS="type=registry,push=true"
  run "$SCRIPT"
  assert_success
  assert_output_value "build_outputs" "type=registry,push=true"
}

@test "default mode keeps a multi-platform request (verify-architecture rejects it later)" {
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/amd64,linux/arm64"
  run "$SCRIPT"
  assert_success
  assert_output_value "platforms" "linux/amd64,linux/arm64"
}

# --- build mode ---

@test "build mode on X64 builds amd64 and pushes by digest" {
  export INPUT_MULTIARCH_MODE="build"
  run "$SCRIPT"
  assert_success
  assert_output_value "arch" "amd64"
  assert_output_value "platforms" "linux/amd64"
  assert_output_value "tags" ""
  assert_output_value "build_outputs" "type=image,name=registry.example.com/private/my-service,push-by-digest=true,name-canonical=true,push=true"
  assert_output_value "cache_suffix" ",scope=amd64"
}

@test "build mode on ARM64 builds arm64 regardless of docker-build-platforms" {
  export INPUT_MULTIARCH_MODE="build"
  export RUNNER_ARCH="ARM64"
  run "$SCRIPT"
  assert_success
  assert_output_value "arch" "arm64"
  assert_output_value "platforms" "linux/arm64"
}

@test "build mode without push keeps tags and does not push by digest" {
  export INPUT_MULTIARCH_MODE="build"
  export INPUT_PUSH="false"
  run "$SCRIPT"
  assert_success
  assert_output_value "platforms" "linux/amd64"
  assert_output_value "tags" "registry.example.com/private/my-service:dev-abcdef12"
  assert_output_value "build_outputs" ""
}

@test "build mode rejects custom docker-build-outputs" {
  export INPUT_MULTIARCH_MODE="build"
  export INPUT_DOCKER_BUILD_OUTPUTS="type=registry,push=true"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "docker-build-outputs cannot be combined"
}

@test "build mode fails on an unsupported runner architecture" {
  export INPUT_MULTIARCH_MODE="build"
  export RUNNER_ARCH="ARM"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "Unsupported runner architecture"
}

# --- merge mode / validation ---

@test "merge mode passes inputs through" {
  export INPUT_MULTIARCH_MODE="merge"
  run "$SCRIPT"
  assert_success
  assert_output_value "platforms" "linux/amd64"
}

@test "fails on an invalid multiarch mode" {
  export INPUT_MULTIARCH_MODE="yes"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "Invalid multiarch-mode"
}
