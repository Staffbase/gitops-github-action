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

out_file=\$(echo "\$*" | sed -n 's/.*-o \([^ ]*\).*/\1/p')

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
      echo '{"schemaVersion": 2}' > "\$out_file"
    else
      echo '{"errors": [{"code": "MANIFEST_UNKNOWN"}]}' > "\$out_file"
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

@test "authenticates with a Bearer token instead of Basic auth when the primary username is oauth2accesstoken" {
  unset INPUT_DOCKER_USERNAME INPUT_DOCKER_PASSWORD
  export INPUT_DOCKER_REGISTRIES="europe-docker.pkg.dev|oauth2accesstoken|gar-token-123"
  export INPUT_DOCKER_REGISTRY_API="https://europe-docker.pkg.dev/v2/"
  create_curl_mock "found"

  run "$SCRIPT"
  assert_success

  run cat "${TEST_TEMP_DIR}/curl_calls.log"
  assert_output --partial "Authorization: Bearer gar-token-123"
  refute_output --partial "-u oauth2accesstoken:gar-token-123"
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

# Digest of the body create_digest_curl_mock serves for a manifest fetched by digest.
served_manifest_digest() {
  echo "sha256:$(echo '{"schemaVersion": 2}' | shasum -a 256 | cut -d' ' -f1)"
}

create_digest_curl_mock() {
  local returned_digest="$1"
  local stored_digest="${2:-$1}"
  cat > "${TEST_TEMP_DIR}/mocks/curl" << MOCK_EOF
#!/usr/bin/env bash
echo "curl \$*" >> "${TEST_TEMP_DIR}/curl_calls.log"
out_file=\$(echo "\$*" | sed -n 's/.*-o \([^ ]*\).*/\1/p')
case "\$*" in
  *"--fail-with-body"*"-X PUT"*)
    headers_file=\$(echo "\$*" | sed 's/.*-D \([^ ]*\).*/\1/')
    printf 'Docker-Content-Digest: %s\n' "$stored_digest" > "\$headers_file"
    echo "PUT OK"
    ;;
  *manifests/sha256:*)
    headers_file=\$(echo "\$*" | sed 's/.*-D \([^ ]*\).*/\1/')
    printf 'Content-Type: application/vnd.oci.image.index.v1+json\nDocker-Content-Digest: %s\n' "$returned_digest" > "\$headers_file"
    echo '{"schemaVersion": 2}' > "\$out_file"
    ;;
  *)
    echo '{"errors": [{"code": "MANIFEST_UNKNOWN"}]}' > "\$out_file"
    ;;
esac
MOCK_EOF
  chmod +x "${TEST_TEMP_DIR}/mocks/curl"
}

@test "retags exactly the given digest without resolving the main/master tag" {
  digest="$(served_manifest_digest)"
  export INPUT_RETAG_DIGEST="$digest"
  create_digest_curl_mock "$digest"

  run "$SCRIPT"
  assert_success
  assert_output_value "digest" "$digest"

  run cat "${TEST_TEMP_DIR}/curl_calls.log"
  assert_output --partial "my-service/manifests/${digest}"
  refute_output --partial "manifests/main-"
  refute_output --partial "manifests/master-"
  assert_output --partial "my-service/manifests/1.0.0"
  assert_output --partial "my-service/manifests/latest"
}

@test "fails without retagging when the registry returns another digest" {
  export INPUT_RETAG_DIGEST="sha256:$(printf 'a%.0s' {1..64})"
  create_digest_curl_mock "sha256:$(printf 'b%.0s' {1..64})"

  run "$SCRIPT"
  assert_failure
  assert_output --partial "The registry returned sha256:bbbb"

  run cat "${TEST_TEMP_DIR}/curl_calls.log"
  refute_output --partial "-X PUT"
}

@test "rejects a malformed digest before any registry call" {
  export INPUT_RETAG_DIGEST="main-abcdef12"
  create_digest_curl_mock "unused"

  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_RETAG_DIGEST must be sha256"
  [ ! -e "${TEST_TEMP_DIR}/curl_calls.log" ]
}

@test "fails when the registry stores the retagged manifest under another digest" {
  export INPUT_RETAG_DIGEST="$(served_manifest_digest)"
  create_digest_curl_mock "$INPUT_RETAG_DIGEST" "sha256:$(printf 'c%.0s' {1..64})"

  run "$SCRIPT"
  assert_failure
  assert_output --partial "my-service:1.0.0 was stored as sha256:cccc"
}

# A registry that, like a real one, addresses manifests by the sha256 of their
# exact bytes: GET serves a newline-terminated manifest and PUT stores whatever
# bytes it received under their own digest.
create_byte_registry_mock() {
  local served_digest="${1:-}"
  printf '{\n  "schemaVersion": 2,\n  "mediaType": "application/vnd.oci.image.index.v1+json",\n  "manifests": []\n}\n' > "${TEST_TEMP_DIR}/manifest.json"
  MANIFEST_DIGEST="sha256:$(shasum -a 256 "${TEST_TEMP_DIR}/manifest.json" | cut -d' ' -f1)"
  cat > "${TEST_TEMP_DIR}/mocks/curl" << MOCK_EOF
#!/usr/bin/env bash
echo "curl \$*" >> "${TEST_TEMP_DIR}/curl_calls.log"
headers_file="" out_file="" data="" put=false
args=("\$@")
for ((i = 0; i < \${#args[@]}; i++)); do
  case "\${args[i]}" in
    -D) headers_file="\${args[i+1]}" ;;
    -o) out_file="\${args[i+1]}" ;;
    -d|--data-binary) data="\${args[i+1]}" ;;
    PUT) put=true ;;
  esac
done
if [[ "\$put" == true ]]; then
  if [[ "\$data" == @* ]]; then cat "\${data#@}"; else printf '%s' "\$data"; fi > "${TEST_TEMP_DIR}/uploaded.json"
  printf 'Docker-Content-Digest: sha256:%s\n' "\$(shasum -a 256 "${TEST_TEMP_DIR}/uploaded.json" | cut -d' ' -f1)" > "\$headers_file"
  exit 0
fi
printf 'Content-Type: application/vnd.oci.image.index.v1+json\nDocker-Content-Digest: %s\n' "${served_digest:-$MANIFEST_DIGEST}" > "\$headers_file"
if [[ -n "\$out_file" ]]; then cat "${TEST_TEMP_DIR}/manifest.json" > "\$out_file"; else cat "${TEST_TEMP_DIR}/manifest.json"; fi
MOCK_EOF
  chmod +x "${TEST_TEMP_DIR}/mocks/curl"
}

@test "retags a newline-terminated manifest byte for byte under the verified digest" {
  create_byte_registry_mock
  export INPUT_RETAG_DIGEST="$MANIFEST_DIGEST"

  run "$SCRIPT"
  assert_success
  assert_output_value "digest" "$MANIFEST_DIGEST"
  cmp "${TEST_TEMP_DIR}/manifest.json" "${TEST_TEMP_DIR}/uploaded.json"
}

@test "fails without retagging when the fetched manifest bytes do not match the digest" {
  create_byte_registry_mock "sha256:$(printf 'a%.0s' {1..64})"
  export INPUT_RETAG_DIGEST="sha256:$(printf 'a%.0s' {1..64})"

  run "$SCRIPT"
  assert_failure
  assert_output --partial "do not match"

  run cat "${TEST_TEMP_DIR}/curl_calls.log"
  refute_output --partial "-X PUT"
}

@test "uploads the fetched manifest bytes unchanged without a verified digest" {
  create_byte_registry_mock

  run "$SCRIPT"
  assert_success
  assert_output_value "digest" "$MANIFEST_DIGEST"
  cmp "${TEST_TEMP_DIR}/manifest.json" "${TEST_TEMP_DIR}/uploaded.json"
}
