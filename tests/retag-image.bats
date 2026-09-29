#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/retag-image.sh"

setup() {
  setup_common
  export GITHUB_SHA="abcdef1234567890"
  export INPUT_DOCKER_REGISTRIES="registry.example.com"
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

  run cat "${TEST_TEMP_DIR}/curl_calls.log"
  assert_output --partial "-u user:pass"
}

@test "retag fails when image is never found within timeout" {
  create_curl_mock "not_found"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "No image found"
  assert_output --partial "within 2 seconds"
}

@test "authenticates with the primary registry's own inline credentials when top-level ones are unset" {
  unset INPUT_DOCKER_USERNAME INPUT_DOCKER_PASSWORD
  export INPUT_DOCKER_REGISTRIES="registry.example.com|inline-user|inline-pass"
  create_curl_mock "found"

  run "$SCRIPT"
  assert_success

  run cat "${TEST_TEMP_DIR}/curl_calls.log"
  assert_output --partial "-u inline-user:inline-pass"
  refute_output --partial "-u user:pass"
}

# --- validation ---

@test "fails when the primary registry has no credentials configured" {
  unset INPUT_DOCKER_USERNAME INPUT_DOCKER_PASSWORD
  run "$SCRIPT"
  assert_failure
  assert_output --partial "No credentials configured for the primary registry"
}

@test "fails when INPUT_DOCKER_IMAGE is missing" {
  unset INPUT_DOCKER_IMAGE
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_IMAGE"
}

@test "fails when INPUT_DOCKER_REGISTRIES is missing" {
  unset INPUT_DOCKER_REGISTRIES
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_DOCKER_REGISTRIES"
}

# --- multi-registry replication ---

create_docker_mock() {
  cat > "${TEST_TEMP_DIR}/mocks/docker" << MOCK_EOF
#!/usr/bin/env bash
echo "docker \$*" >> "${TEST_TEMP_DIR}/docker_calls.log"
MOCK_EOF
  chmod +x "${TEST_TEMP_DIR}/mocks/docker"
}

@test "replicates release and latest tags to additional registries" {
  create_curl_mock "found"
  create_docker_mock
  export INPUT_DOCKER_REGISTRIES=$'registry.example.com|user|pass\nother.example.com|user2|pass2'

  run "$SCRIPT"
  assert_success

  run cat "${TEST_TEMP_DIR}/docker_calls.log"
  assert_output --partial "buildx imagetools create --tag other.example.com/my-service:1.0.0 --tag other.example.com/my-service:latest registry.example.com/my-service@sha256:abc123def456"
}

@test "does not call docker when only a single registry is configured" {
  create_curl_mock "found"
  create_docker_mock

  run "$SCRIPT"
  assert_success
  run test -f "${TEST_TEMP_DIR}/docker_calls.log"
  assert_failure
}
