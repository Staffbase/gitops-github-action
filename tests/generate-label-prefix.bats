#!/usr/bin/env bats

load 'test_helper/setup'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/generate-label-prefix.sh"

setup() {
  setup_common
}

teardown() {
  teardown_common
}

@test "label_prefix defaults to reversed deploy.staffbase.com" {
  unset INPUT_DEPLOYMENT_DOMAIN
  run "$SCRIPT"
  assert_success
  assert_output_value "label_prefix" "com.staffbase.deploy"
}

@test "label_prefix reverses a custom deployment domain" {
  export INPUT_DEPLOYMENT_DOMAIN="deploy.example.org"
  run "$SCRIPT"
  assert_success
  assert_output_value "label_prefix" "org.example.deploy"
}
