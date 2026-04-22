#!/usr/bin/env bash
# Common test helper for bats tests.
# Provides mock setup, temporary directories, and assertion helpers.

load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

setup_common() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export GITHUB_OUTPUT="${TEST_TEMP_DIR}/github_output"
  touch "$GITHUB_OUTPUT"
}

teardown_common() {
  rm -rf "$TEST_TEMP_DIR"
}

# Assert that a specific output was written to GITHUB_OUTPUT
assert_output_value() {
  local name="$1"
  local expected="$2"
  local actual
  actual=$(grep "^${name}=" "$GITHUB_OUTPUT" | head -1 | cut -d'=' -f2-)
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected output ${name}='${expected}', got '${actual}'" >&2
    echo "Full GITHUB_OUTPUT contents:" >&2
    cat "$GITHUB_OUTPUT" >&2
    return 1
  fi
}

# Get value of a specific output from GITHUB_OUTPUT
get_output_value() {
  local name="$1"
  grep "^${name}=" "$GITHUB_OUTPUT" | head -1 | cut -d'=' -f2-
}

# Create a mock command that records calls and returns configured output
create_mock() {
  local cmd_name="$1"
  local mock_script="${TEST_TEMP_DIR}/mocks/${cmd_name}"
  mkdir -p "${TEST_TEMP_DIR}/mocks"
  cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "$0 $*" >> "${MOCK_CALLS_DIR:-/tmp}/mock_calls.log"
MOCK_EOF
  chmod +x "$mock_script"
  export PATH="${TEST_TEMP_DIR}/mocks:$PATH"
  export MOCK_CALLS_DIR="$TEST_TEMP_DIR"
}
