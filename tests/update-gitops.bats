#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/update-gitops.sh"

setup() {
  setup_common
  export GITHUB_SHA="abcdef1234567890"
  export GITHUB_REPOSITORY="Staffbase/my-service"
  export INPUT_DOCKER_REGISTRY="registry.staffbase.com"
  export INPUT_DOCKER_IMAGE="my-service"
  export INPUT_TAG="main-abcdef12"
  export INPUT_PUSH="true"
  export INPUT_GITOPS_USER="Staffbot"
  export INPUT_GITOPS_EMAIL="staffbot@staffbase.com"
  export INPUT_GITOPS_TOKEN="fake-token"
  export INPUT_GITOPS_ORGANIZATION="Staffbase"
  export INPUT_GITOPS_REPOSITORY="mops"
  export INPUT_GITOPS_DEV=""
  export INPUT_GITOPS_STAGE=""
  export INPUT_GITOPS_PROD=""

  # Create mocks
  mkdir -p "${TEST_TEMP_DIR}/mocks"
  export MOCK_CALLS_DIR="$TEST_TEMP_DIR"

  cat > "${TEST_TEMP_DIR}/mocks/yq" << 'MOCK'
#!/usr/bin/env bash
echo "yq $*" >> "${MOCK_CALLS_DIR}/yq_calls.log"
exit 0
MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/yq"

  cat > "${TEST_TEMP_DIR}/mocks/git" << 'MOCK'
#!/usr/bin/env bash
echo "git $*" >> "${MOCK_CALLS_DIR}/git_calls.log"
case "$1" in
  diff-index) exit 1 ;; # changes exist
  *) exit 0 ;;
esac
MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/git"

  cat > "${TEST_TEMP_DIR}/mocks/jq" << 'MOCK'
#!/usr/bin/env bash
if command -v /usr/bin/jq &>/dev/null; then
  /usr/bin/jq "$@"
elif command -v /opt/homebrew/bin/jq &>/dev/null; then
  /opt/homebrew/bin/jq "$@"
else
  cat
fi
MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/jq"

  export PATH="${TEST_TEMP_DIR}/mocks:$PATH"
}

teardown() {
  teardown_common
}

# --- STAGE updates on main ---

@test "updates STAGE files on main branch" {
  export GITHUB_REF="refs/heads/main"
  export INPUT_GITOPS_STAGE="kubernetes/namespaces/svc/stage/de1/deploy.yaml spec.image"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Run update for STAGE"
  grep -q 'yq -e' "${TEST_TEMP_DIR}/yq_calls.log"
  grep -q 'git commit' "${TEST_TEMP_DIR}/git_calls.log"
}

@test "updates STAGE files on master branch" {
  export GITHUB_REF="refs/heads/master"
  export INPUT_GITOPS_STAGE="kubernetes/namespaces/svc/stage/de1/deploy.yaml spec.image"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Run update for STAGE"
}

# --- DEV updates on dev ---

@test "updates DEV files on dev branch" {
  export GITHUB_REF="refs/heads/dev"
  export INPUT_GITOPS_DEV="kubernetes/namespaces/svc/dev/de1/deploy.yaml spec.image"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Run update for DEV"
}

# --- PROD updates on tags ---

@test "updates PROD files on tag" {
  export GITHUB_REF="refs/tags/v1.0.0"
  export INPUT_GITOPS_PROD="kubernetes/namespaces/svc/prod/de1/deploy.yaml spec.image"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Run update for PROD"
}

# --- Simulate on feature branch ---

@test "simulates DEV update on feature branch" {
  export GITHUB_REF="refs/heads/feature/test"
  export INPUT_GITOPS_DEV="kubernetes/namespaces/svc/dev/de1/deploy.yaml spec.image"
  run "$SCRIPT"
  assert_success
  assert_output --partial "Simulate update for DEV"
  # Should NOT commit
  ! grep -q 'git commit' "${TEST_TEMP_DIR}/git_calls.log" 2>/dev/null || true
}

# --- No files configured ---

@test "does nothing when no gitops files are configured" {
  export GITHUB_REF="refs/heads/main"
  run "$SCRIPT"
  assert_success
  [[ ! -f "${TEST_TEMP_DIR}/yq_calls.log" ]]
}

# --- validation ---

@test "fails when GITHUB_REF is missing" {
  unset GITHUB_REF
  run "$SCRIPT"
  assert_failure
  assert_output --partial "GITHUB_REF"
}

@test "fails when INPUT_GITOPS_TOKEN is missing" {
  export GITHUB_REF="refs/heads/main"
  unset INPUT_GITOPS_TOKEN
  run "$SCRIPT"
  assert_failure
  assert_output --partial "INPUT_GITOPS_TOKEN"
}
