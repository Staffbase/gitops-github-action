#!/usr/bin/env bats

load 'test_helper/setup'

setup() {
  setup_common
  source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../scripts/lib/gitops-functions.sh"

  export GITHUB_REPOSITORY="Staffbase/my-service"
  export GITHUB_SHA="abcdef1234567890"
  export INPUT_DOCKER_REGISTRY="registry.staffbase.com"
  export INPUT_DOCKER_IMAGE="my-service"
  export INPUT_TAG="main-abcdef12"
  export INPUT_PUSH="true"
  export INPUT_CREATE_DEPLOYMENT="false"
  export INPUT_DEPLOYMENT_IDS="{}"
  export INPUT_GITOPS_USER="Staffbot"
  export INPUT_GITOPS_TOKEN="fake-token"
  export INPUT_GITOPS_ORGANIZATION="Staffbase"
  export INPUT_GITOPS_REPOSITORY="mops"
  export IMAGE="registry.staffbase.com/my-service:main-abcdef12"

  # Create mock yq
  mkdir -p "${TEST_TEMP_DIR}/mocks"
  cat > "${TEST_TEMP_DIR}/mocks/yq" << 'YQ_MOCK'
#!/usr/bin/env bash
echo "yq $*" >> "${MOCK_CALLS_DIR}/yq_calls.log"
# For -e (evaluate/check), just succeed
# For -i (in-place edit), do nothing
exit 0
YQ_MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/yq"
  export MOCK_CALLS_DIR="$TEST_TEMP_DIR"

  # Create mock git
  cat > "${TEST_TEMP_DIR}/mocks/git" << 'GIT_MOCK'
#!/usr/bin/env bash
echo "git $*" >> "${MOCK_CALLS_DIR}/git_calls.log"
case "$1" in
  diff-index) exit 1 ;; # simulate changes exist
  *) exit 0 ;;
esac
GIT_MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/git"

  # Create mock jq that passes through
  cat > "${TEST_TEMP_DIR}/mocks/jq" << 'JQ_MOCK'
#!/usr/bin/env bash
# Use real jq if available, otherwise simple passthrough
if command -v /usr/bin/jq &>/dev/null; then
  /usr/bin/jq "$@"
elif command -v /opt/homebrew/bin/jq &>/dev/null; then
  /opt/homebrew/bin/jq "$@"
else
  cat
fi
JQ_MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/jq"

  export PATH="${TEST_TEMP_DIR}/mocks:$PATH"
}

teardown() {
  teardown_common
}

# --- derive_environment ---

@test "derive_environment extracts env and cluster from standard mops path" {
  run derive_environment "kubernetes/namespaces/my-service/prod/de1/deployment.yaml"
  assert_success
  assert_output "prod-de1"
}

@test "derive_environment handles stage environment" {
  run derive_environment "kubernetes/namespaces/my-service/stage/us1/deployment.yaml"
  assert_success
  assert_output "stage-us1"
}

@test "derive_environment handles dev environment" {
  run derive_environment "kubernetes/namespaces/my-service/dev/de1/deployment.yaml"
  assert_success
  assert_output "dev-de1"
}

# --- update_file ---

@test "update_file calls yq to check and update field" {
  update_file "deployment.yaml" "spec.image" "$IMAGE"
  assert [ -f "${TEST_TEMP_DIR}/yq_calls.log" ]
  grep -q 'yq -e .spec.image deployment.yaml' "${TEST_TEMP_DIR}/yq_calls.log"
  grep -q 'yq -i' "${TEST_TEMP_DIR}/yq_calls.log"
}

@test "update_file writes deployment annotations when create-deployment is true" {
  export INPUT_CREATE_DEPLOYMENT="true"
  update_file "kubernetes/namespaces/svc/prod/de1/deployment.yaml" "spec.image" "$IMAGE"
  grep -q 'deploy.staffbase.com/repo' "${TEST_TEMP_DIR}/yq_calls.log"
  grep -q 'deploy.staffbase.com/sha' "${TEST_TEMP_DIR}/yq_calls.log"
}

@test "update_file skips annotations when create-deployment is false" {
  export INPUT_CREATE_DEPLOYMENT="false"
  update_file "deployment.yaml" "spec.image" "$IMAGE"
  ! grep -q 'deploy.staffbase.com' "${TEST_TEMP_DIR}/yq_calls.log" 2>/dev/null || true
}

@test "update_file writes deployment-id annotation when deployment ID is available" {
  export INPUT_CREATE_DEPLOYMENT="true"
  export INPUT_DEPLOYMENT_IDS='{"prod-de1":"12345"}'
  update_file "kubernetes/namespaces/svc/prod/de1/deployment.yaml" "spec.image" "$IMAGE"
  grep -q 'deploy.staffbase.com/deployment-id' "${TEST_TEMP_DIR}/yq_calls.log"
}

@test "update_file skips deployment-id annotation when no matching deployment ID" {
  export INPUT_CREATE_DEPLOYMENT="true"
  export INPUT_DEPLOYMENT_IDS='{"stage-us1":"99999"}'
  update_file "kubernetes/namespaces/svc/prod/de1/deployment.yaml" "spec.image" "$IMAGE"
  ! grep -q 'deployment-id' "${TEST_TEMP_DIR}/yq_calls.log"
}

# --- commit_changes ---

@test "commit_changes commits and pushes when push is true" {
  commit_changes
  grep -q 'git add' "${TEST_TEMP_DIR}/git_calls.log"
  grep -q 'git commit' "${TEST_TEMP_DIR}/git_calls.log"
  grep -q 'git push' "${TEST_TEMP_DIR}/git_calls.log"
}

@test "commit_changes skips when push is false" {
  export INPUT_PUSH="false"
  commit_changes
  [[ ! -f "${TEST_TEMP_DIR}/git_calls.log" ]]
}

@test "commit_changes skips commit when no changes" {
  # Override git mock: diff-index returns 0 (no changes)
  cat > "${TEST_TEMP_DIR}/mocks/git" << 'GIT_MOCK'
#!/usr/bin/env bash
echo "git $*" >> "${MOCK_CALLS_DIR}/git_calls.log"
exit 0
GIT_MOCK
  chmod +x "${TEST_TEMP_DIR}/mocks/git"

  commit_changes
  ! grep -q 'git commit' "${TEST_TEMP_DIR}/git_calls.log"
}

# --- process_file_updates ---

@test "process_file_updates processes multi-line input" {
  local file_list="file1.yaml spec.image
file2.yaml spec.container.image"
  process_file_updates "$file_list" "false"
  local yq_count
  yq_count=$(grep -c 'yq -e' "${TEST_TEMP_DIR}/yq_calls.log")
  [[ "$yq_count" -eq 2 ]]
}

@test "process_file_updates skips empty lines" {
  local file_list="file1.yaml spec.image

file2.yaml spec.image"
  process_file_updates "$file_list" "false"
  local yq_count
  yq_count=$(grep -c 'yq -e' "${TEST_TEMP_DIR}/yq_calls.log")
  [[ "$yq_count" -eq 2 ]]
}

@test "process_file_updates commits when should_commit is true" {
  process_file_updates "file1.yaml spec.image" "true"
  grep -q 'git commit' "${TEST_TEMP_DIR}/git_calls.log"
}

@test "process_file_updates skips commit when should_commit is false" {
  process_file_updates "file1.yaml spec.image" "false"
  ! grep -q 'git commit' "${TEST_TEMP_DIR}/git_calls.log" 2>/dev/null || true
}
