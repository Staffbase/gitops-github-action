#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/login-registries.sh"

setup() {
  setup_common
  export INPUT_DOCKER_REGISTRIES="registry.example.com"
  export INPUT_DOCKER_USERNAME="user"
  export INPUT_DOCKER_PASSWORD="pass"
  create_mock docker
}

teardown() {
  teardown_common
}

docker_calls() {
  cat "${MOCK_CALLS_DIR}/mock_calls.log" 2>/dev/null
}

@test "logs in to a single registry" {
  run "$SCRIPT"
  assert_success
  run docker_calls
  assert_output --partial "login registry.example.com --username user --password-stdin"
}

@test "logs in to every registry in a multi-registry list" {
  export INPUT_DOCKER_REGISTRIES=$'registry.example.com|user1|pass1\nother.example.com|user2|pass2'
  run "$SCRIPT"
  assert_success
  run docker_calls
  assert_output --partial "login registry.example.com --username user1 --password-stdin"
  assert_output --partial "login other.example.com --username user2 --password-stdin"
}

@test "logs in to the bare host when a registry entry carries a path prefix" {
  export INPUT_DOCKER_REGISTRIES="europe-docker.pkg.dev/staffbase-artifacts/images-publish|oauth2accesstoken|token123"
  run "$SCRIPT"
  assert_success
  run docker_calls
  assert_output --partial "login europe-docker.pkg.dev --username oauth2accesstoken --password-stdin"
  refute_output --partial "login europe-docker.pkg.dev/staffbase-artifacts"
}

@test "skips entries missing credentials" {
  export INPUT_DOCKER_REGISTRIES=$'registry.example.com|user1|pass1\nother.example.com'
  unset INPUT_DOCKER_USERNAME INPUT_DOCKER_PASSWORD
  run "$SCRIPT"
  assert_success
  assert_output --partial "Skipping login for 'other.example.com'"
  run docker_calls
  assert_output --partial "login registry.example.com --username user1 --password-stdin"
  refute_output --partial "other.example.com"
}

@test "fails when INPUT_DOCKER_REGISTRIES is missing" {
  unset INPUT_DOCKER_REGISTRIES
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_REGISTRIES"
}
