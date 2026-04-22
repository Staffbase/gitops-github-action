#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/generate-tags.sh"

setup() {
  setup_common
  export GITHUB_SHA="abcdef1234567890"
  export INPUT_DOCKER_REGISTRY="registry.staffbase.com"
  export INPUT_DOCKER_IMAGE="my-service"
  export INPUT_DOCKER_CUSTOM_TAG=""
  export INPUT_DOCKER_DISABLE_RETAGGING="false"
}

teardown() {
  teardown_common
}

# --- main branch ---

@test "main branch generates correct tag" {
  export GITHUB_REF="refs/heads/main"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "main-abcdef12"
  assert_output_value "latest" "main"
  assert_output_value "push" "true"
  assert_output_value "build" "true"
}

# --- master branch ---

@test "master branch generates correct tag" {
  export GITHUB_REF="refs/heads/master"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "master-abcdef12"
  assert_output_value "latest" "master"
  assert_output_value "push" "true"
  assert_output_value "build" "true"
}

# --- dev branch ---

@test "dev branch generates correct tag" {
  export GITHUB_REF="refs/heads/dev"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "dev-abcdef12"
  assert_output_value "latest" "dev"
  assert_output_value "push" "true"
  assert_output_value "build" "true"
}

# --- version tag ---

@test "version tag v1.2.3 generates correct tag" {
  export GITHUB_REF="refs/tags/v1.2.3"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "1.2.3"
  assert_output_value "latest" "latest"
  assert_output_value "push" "true"
}

@test "version tag uses docker-disable-retagging for build flag" {
  export GITHUB_REF="refs/tags/v1.2.3"
  export INPUT_DOCKER_DISABLE_RETAGGING="true"
  run "$SCRIPT"
  assert_success
  assert_output_value "build" "true"
}

@test "version tag defaults build to false when retagging enabled" {
  export GITHUB_REF="refs/tags/v1.2.3"
  export INPUT_DOCKER_DISABLE_RETAGGING="false"
  run "$SCRIPT"
  assert_success
  assert_output_value "build" "false"
}

# --- non-version tag ---

@test "non-version tag generates correct tag" {
  export GITHUB_REF="refs/tags/release-1"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "release-1"
  assert_output_value "latest" "latest"
  assert_output_value "push" "true"
}

# --- feature branch ---

@test "feature branch generates SHA tag with no push" {
  export GITHUB_REF="refs/heads/feature/my-feature"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "abcdef12"
  assert_output_value "push" "false"
  assert_output_value "build" "true"
  assert_output_value "latest" ""
}

# --- custom tag ---

@test "custom tag overrides branch logic" {
  export GITHUB_REF="refs/heads/main"
  export INPUT_DOCKER_CUSTOM_TAG="my-custom-tag"
  run "$SCRIPT"
  assert_success
  assert_output_value "tag" "my-custom-tag"
  assert_output_value "latest" "latest"
  assert_output_value "push" "true"
}

@test "custom tag with retagging disabled sets build to true" {
  export GITHUB_REF="refs/heads/main"
  export INPUT_DOCKER_CUSTOM_TAG="my-custom-tag"
  export INPUT_DOCKER_DISABLE_RETAGGING="true"
  run "$SCRIPT"
  assert_success
  assert_output_value "build" "true"
}

@test "custom tag with retagging enabled sets build to false" {
  export GITHUB_REF="refs/heads/main"
  export INPUT_DOCKER_CUSTOM_TAG="my-custom-tag"
  export INPUT_DOCKER_DISABLE_RETAGGING="false"
  run "$SCRIPT"
  assert_success
  assert_output_value "build" "false"
}

# --- tag_list format ---

@test "tag_list includes registry and image" {
  export GITHUB_REF="refs/heads/main"
  run "$SCRIPT"
  assert_success
  local tag_list
  tag_list=$(get_output_value "tag_list")
  [[ "$tag_list" == "registry.staffbase.com/my-service:main-abcdef12,registry.staffbase.com/my-service:main" ]]
}

@test "tag_list has no latest suffix for feature branches" {
  export GITHUB_REF="refs/heads/feature/test"
  run "$SCRIPT"
  assert_success
  local tag_list
  tag_list=$(get_output_value "tag_list")
  [[ "$tag_list" == "registry.staffbase.com/my-service:abcdef12" ]]
}

# --- validation ---

@test "fails when GITHUB_REF is missing" {
  unset GITHUB_REF
  run "$SCRIPT"
  assert_failure
  assert_output --partial "GITHUB_REF"
}

@test "fails when INPUT_DOCKER_IMAGE is missing" {
  export GITHUB_REF="refs/heads/main"
  unset INPUT_DOCKER_IMAGE
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_IMAGE"
}
