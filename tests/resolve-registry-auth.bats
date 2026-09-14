#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/resolve-registry-auth.sh"

setup() {
  setup_common
  unset INPUT_GCP_ACCESS_TOKEN INPUT_GCP_WORKLOAD_IDENTITY_PROVIDER \
    INPUT_GCP_SERVICE_ACCOUNT INPUT_DOCKER_USERNAME INPUT_DOCKER_PASSWORD
}

teardown() {
  teardown_common
}

# --- basic auth (Harbor and anything else username/password) ---

@test "username and password select basic auth" {
  export INPUT_DOCKER_USERNAME="robot\$ci"
  export INPUT_DOCKER_PASSWORD="secret"
  run "$SCRIPT"
  assert_success
  assert_output_value "authenticated" "true"
  assert_output_value "mode" "basic"
}

# --- workload identity federation ---

@test "a Google access token selects federated auth" {
  export INPUT_GCP_ACCESS_TOKEN="ya29.token"
  export INPUT_GCP_WORKLOAD_IDENTITY_PROVIDER="projects/1/locations/global/workloadIdentityPools/p/providers/gh"
  export INPUT_GCP_SERVICE_ACCOUNT="ci@example.iam.gserviceaccount.com"
  run "$SCRIPT"
  assert_success
  assert_output_value "authenticated" "true"
  assert_output_value "mode" "wif"
}

@test "a Google access token wins over docker credentials" {
  export INPUT_GCP_ACCESS_TOKEN="ya29.token"
  export INPUT_DOCKER_USERNAME="robot\$ci"
  export INPUT_DOCKER_PASSWORD="secret"
  run "$SCRIPT"
  assert_success
  assert_output_value "mode" "wif"
}

# --- half-configured credentials fail instead of silently skipping ---

@test "a username without a password fails" {
  export INPUT_DOCKER_USERNAME="robot\$ci"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "docker-password is empty"
}

@test "a password without a username fails" {
  export INPUT_DOCKER_PASSWORD="secret"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "docker-username is empty"
}

@test "a WIF provider without a service account fails" {
  export INPUT_GCP_WORKLOAD_IDENTITY_PROVIDER="projects/1/locations/global/workloadIdentityPools/p/providers/gh"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "gcp-service-account is empty"
}

@test "a service account without a WIF provider fails" {
  export INPUT_GCP_SERVICE_ACCOUNT="ci@example.iam.gserviceaccount.com"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "gcp-workload-identity-provider is empty"
}

@test "complete WIF inputs that produced no token name the missing permission" {
  export INPUT_GCP_WORKLOAD_IDENTITY_PROVIDER="projects/1/locations/global/workloadIdentityPools/p/providers/gh"
  export INPUT_GCP_SERVICE_ACCOUNT="ci@example.iam.gserviceaccount.com"
  run "$SCRIPT"
  assert_failure
  assert_output --partial "id-token: write"
}

# --- no credentials at all is the documented deploy-only configuration ---

@test "no credentials warns and skips instead of failing" {
  run "$SCRIPT"
  assert_success
  assert_output_value "authenticated" "false"
  assert_output_value "mode" "none"
  assert_output --partial "::warning::"
  assert_output --partial "deploy-only"
}

@test "the resolved password is never written to an output" {
  export INPUT_DOCKER_USERNAME="robot\$ci"
  export INPUT_DOCKER_PASSWORD="super-secret"
  run "$SCRIPT"
  assert_success
  refute_output --partial "super-secret"
  run grep -c "super-secret" "$GITHUB_OUTPUT"
  assert_output "0"
}
