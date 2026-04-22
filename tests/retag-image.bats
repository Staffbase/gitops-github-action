#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/retag-image.sh"

setup() {
  setup_common
  export GITHUB_SHA="abcdef1234567890"
  export INPUT_DOCKER_USERNAME="user"
  export INPUT_DOCKER_PASSWORD="pass"
  export INPUT_DOCKER_REGISTRY_API="https://registry.example.com/v2/"
  export INPUT_DOCKER_IMAGE="my-service"
  export INPUT_TAG="1.0.0"
  export INPUT_LATEST="latest"
  export RETAG_TIMEOUT_SECONDS="2"
  export RETAG_POLL_INTERVAL="0"

  # Create mock curl
  mkdir -p "${TEST_TEMP_DIR}/mocks"
  export PATH="${TEST_TEMP_DIR}/mocks:$PATH"
}

teardown() {
  teardown_common
}

create_curl_mock() {
  local behavior="$1"
  cat > "${TEST_TEMP_DIR}/mocks/curl" << MOCK_EOF
#!/usr/bin/env bash
# Record call
echo "curl \$*" >> "${TEST_TEMP_DIR}/curl_calls.log"

# Handle different call patterns
case "\$*" in
  *manifests/master-*|*manifests/main-*)
    if [[ "$behavior" == "found" ]]; then
      # Write mock headers
      if [[ "\$*" == *"-D "* ]]; then
        headers_file=\$(echo "\$*" | sed 's/.*-D \([^ ]*\).*/\1/')
        cat > "\$headers_file" << 'HEADERS'
Content-Type: application/vnd.docker.distribution.manifest.v2+json
Docker-Content-Digest: sha256:abc123def456
HEADERS
      fi
      echo '{"schemaVersion": 2}'
    else
      echo '{"errors": [{"code": "MANIFEST_UNKNOWN"}]}'
    fi
    ;;
  *"--fail-with-body"*"-X PUT"*)
    echo "PUT OK"
    ;;
esac
MOCK_EOF
  chmod +x "${TEST_TEMP_DIR}/mocks/curl"
}

@test "retag succeeds when image is found immediately" {
  create_curl_mock "found"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Image found for"
  assert_output --partial "Retagging image"
  assert_output_value "digest" "sha256:abc123def456"
}

@test "retag fails when image is never found within timeout" {
  create_curl_mock "not_found"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "No image found"
  assert_output --partial "within 2 seconds"
}

# --- validation ---

@test "fails when INPUT_DOCKER_USERNAME is missing" {
  unset INPUT_DOCKER_USERNAME
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_USERNAME"
}

@test "fails when INPUT_DOCKER_IMAGE is missing" {
  unset INPUT_DOCKER_IMAGE
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_IMAGE"
}
