#!/usr/bin/env bats

load 'test_helper/setup'

setup() {
  setup_common
  source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
}

teardown() {
  teardown_common
}

# --- log_info ---

@test "log_info outputs notice format" {
  run log_info "test message"
  assert_success
  assert_output "::notice::test message"
}

# --- log_warn ---

@test "log_warn outputs warning format" {
  run log_warn "warning message"
  assert_success
  assert_output "::warning::warning message"
}

# --- log_error ---

@test "log_error outputs error format to stderr" {
  run log_error "error message"
  assert_success
  assert_output "::error::error message"
}

# --- set_output ---

@test "set_output writes to GITHUB_OUTPUT" {
  set_output "my_key" "my_value"
  assert_output_value "my_key" "my_value"
}

@test "set_output handles empty value" {
  set_output "empty_key" ""
  assert_output_value "empty_key" ""
}

@test "set_output handles value with special characters" {
  set_output "special" "hello=world,foo:bar"
  assert_output_value "special" "hello=world,foo:bar"
}

@test "set_output falls back to stdout when GITHUB_OUTPUT is unset" {
  unset GITHUB_OUTPUT
  run set_output "key" "value"
  assert_success
  assert_output "OUTPUT key=value"
}

# --- require_env ---

@test "require_env succeeds when variable is set" {
  export MY_VAR="hello"
  run require_env "MY_VAR"
  assert_success
}

@test "require_env fails when variable is empty" {
  export MY_VAR=""
  run require_env "MY_VAR"
  assert_failure
  assert_output --partial "Required environment variable 'MY_VAR'"
}

@test "require_env fails when variable is unset" {
  unset MY_VAR
  run require_env "MY_VAR"
  assert_failure
  assert_output --partial "Required environment variable 'MY_VAR'"
}

# --- require_tool ---

@test "require_tool succeeds for existing tool" {
  run require_tool "bash"
  assert_success
}

@test "require_tool fails for non-existing tool" {
  run require_tool "nonexistent_tool_xyz"
  assert_failure
  assert_output --partial "Required tool 'nonexistent_tool_xyz'"
}

# --- retry_with_backoff ---

@test "retry_with_backoff succeeds on first try" {
  run retry_with_backoff 3 1 true
  assert_success
}

@test "retry_with_backoff fails after exhausting attempts" {
  run retry_with_backoff 2 0 false
  assert_failure
  assert_output --partial "failed after 2 attempts"
}

@test "retry_with_backoff succeeds on later attempt" {
  COUNTER_FILE="${TEST_TEMP_DIR}/counter"
  echo "0" > "$COUNTER_FILE"

  flaky_command() {
    local count
    count=$(cat "$COUNTER_FILE")
    count=$((count + 1))
    echo "$count" > "$COUNTER_FILE"
    [[ $count -ge 3 ]]
  }
  export -f flaky_command
  export COUNTER_FILE

  run retry_with_backoff 5 0 flaky_command
  assert_success
}
