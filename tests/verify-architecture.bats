#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/verify-architecture.sh"

setup() {
  setup_common
}

teardown() {
  teardown_common
}

# --- X64 runner ---

@test "X64 runner with amd64 target passes" {
  export RUNNER_ARCH="X64"
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/amd64"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Architecture match verified"
}

@test "X64 runner with arm64 target fails" {
  export RUNNER_ARCH="X64"
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/arm64"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "requires emulation"
}

@test "X64 runner with multi-arch target fails" {
  export RUNNER_ARCH="X64"
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/amd64,linux/arm64"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "requires emulation"
}

# --- ARM64 runner ---

@test "ARM64 runner with arm64 target passes" {
  export RUNNER_ARCH="ARM64"
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/arm64"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Architecture match verified"
}

@test "ARM64 runner with amd64 target fails" {
  export RUNNER_ARCH="ARM64"
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/amd64"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "requires emulation"
}

# --- validation ---

@test "fails when RUNNER_ARCH is missing" {
  unset RUNNER_ARCH
  export INPUT_DOCKER_BUILD_PLATFORMS="linux/amd64"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "RUNNER_ARCH"
}

@test "fails when INPUT_DOCKER_BUILD_PLATFORMS is missing" {
  export RUNNER_ARCH="X64"
  unset INPUT_DOCKER_BUILD_PLATFORMS
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_BUILD_PLATFORMS"
}
