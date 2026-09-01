#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/merge-manifests.sh"

AMD_DIGEST="1111111111111111111111111111111111111111111111111111111111111111"
ARM_DIGEST="2222222222222222222222222222222222222222222222222222222222222222"

setup() {
  setup_common
  export INPUT_DOCKER_REGISTRY="registry.example.com"
  export INPUT_DOCKER_IMAGE="private/my-service"
  export INPUT_TAG_LIST="registry.example.com/private/my-service:dev-1,registry.example.com/private/my-service:dev"
  export INPUT_DIGESTS_PATH="${TEST_TEMP_DIR}/digests"
  mkdir -p "$INPUT_DIGESTS_PATH"

  mkdir -p "${TEST_TEMP_DIR}/mocks"
  export PATH="${TEST_TEMP_DIR}/mocks:$PATH"
  cat > "${TEST_TEMP_DIR}/mocks/docker" << MOCK_EOF
#!/usr/bin/env bash
echo "docker \$*" >> "${TEST_TEMP_DIR}/docker_calls.log"
if [[ "\$*" == *"inspect"* ]]; then
  echo '{"digest":"sha256:deadbeef"}'
fi
MOCK_EOF
  chmod +x "${TEST_TEMP_DIR}/mocks/docker"
}

teardown() {
  teardown_common
}

@test "merges all digests under all tags and reports the index digest" {
  touch "${INPUT_DIGESTS_PATH}/${AMD_DIGEST}" "${INPUT_DIGESTS_PATH}/${ARM_DIGEST}"
  run "$SCRIPT"
  assert_success
  assert_output_value "digest" "sha256:deadbeef"

  run cat "${TEST_TEMP_DIR}/docker_calls.log"
  assert_output --partial "--tag registry.example.com/private/my-service:dev-1 --tag registry.example.com/private/my-service:dev"
  assert_output --partial "registry.example.com/private/my-service@sha256:${AMD_DIGEST}"
  assert_output --partial "registry.example.com/private/my-service@sha256:${ARM_DIGEST}"
}

@test "ignores files that are not digests" {
  touch "${INPUT_DIGESTS_PATH}/${AMD_DIGEST}" "${INPUT_DIGESTS_PATH}/README.md"
  run "$SCRIPT"
  assert_success

  run cat "${TEST_TEMP_DIR}/docker_calls.log"
  refute_output --partial "README.md"
}

@test "fails when no digests were uploaded" {
  run "$SCRIPT"
  assert_failure
  assert_output --partial "No digests found"
}

@test "fails when INPUT_TAG_LIST is missing" {
  touch "${INPUT_DIGESTS_PATH}/${AMD_DIGEST}"
  unset INPUT_TAG_LIST
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_TAG_LIST"
}
