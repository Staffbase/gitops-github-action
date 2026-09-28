#!/usr/bin/env bats

load 'test_helper/setup'

setup() {
  setup_common
  # shellcheck source=../scripts/lib/registries.sh
  source "${BATS_TEST_DIRNAME}/../scripts/lib/registries.sh"
}

teardown() {
  teardown_common
}

@test "parses a single plain registry entry" {
  export INPUT_DOCKER_REGISTRIES="registry.example.com"
  export INPUT_DOCKER_USERNAME="user"
  export INPUT_DOCKER_PASSWORD="pass"

  resolve_registries

  [ "${#REGISTRIES[@]}" -eq 1 ]
  [ "$(registry_field "${REGISTRIES[0]}" 1)" = "registry.example.com" ]
  [ "$(registry_field "${REGISTRIES[0]}" 2)" = "user" ]
  [ "$(registry_field "${REGISTRIES[0]}" 3)" = "pass" ]
}

@test "parses a single registry entry with inline credentials" {
  export INPUT_DOCKER_REGISTRIES="registry.example.com|user|pass"

  resolve_registries

  [ "${#REGISTRIES[@]}" -eq 1 ]
  [ "$(registry_field "${REGISTRIES[0]}" 1)" = "registry.example.com" ]
  [ "$(registry_field "${REGISTRIES[0]}" 2)" = "user" ]
  [ "$(registry_field "${REGISTRIES[0]}" 3)" = "pass" ]
}

@test "parses multiple registries with per-entry credentials" {
  export INPUT_DOCKER_USERNAME="default-user"
  export INPUT_DOCKER_PASSWORD="default-pass"
  export INPUT_DOCKER_REGISTRIES=$'registry.example.com|user1|pass1\nother.example.com|user2|pass2'

  resolve_registries

  [ "${#REGISTRIES[@]}" -eq 2 ]
  [ "$(registry_field "${REGISTRIES[0]}" 1)" = "registry.example.com" ]
  [ "$(registry_field "${REGISTRIES[0]}" 2)" = "user1" ]
  [ "$(registry_field "${REGISTRIES[0]}" 3)" = "pass1" ]
  [ "$(registry_field "${REGISTRIES[1]}" 1)" = "other.example.com" ]
  [ "$(registry_field "${REGISTRIES[1]}" 2)" = "user2" ]
  [ "$(registry_field "${REGISTRIES[1]}" 3)" = "pass2" ]
}

@test "falls back to default credentials when an entry omits them" {
  export INPUT_DOCKER_USERNAME="default-user"
  export INPUT_DOCKER_PASSWORD="default-pass"
  export INPUT_DOCKER_REGISTRIES=$'registry.example.com\nother.example.com|user2|pass2'

  resolve_registries

  [ "${#REGISTRIES[@]}" -eq 2 ]
  [ "$(registry_field "${REGISTRIES[0]}" 1)" = "registry.example.com" ]
  [ "$(registry_field "${REGISTRIES[0]}" 2)" = "default-user" ]
  [ "$(registry_field "${REGISTRIES[0]}" 3)" = "default-pass" ]
}

@test "ignores blank lines in INPUT_DOCKER_REGISTRIES" {
  export INPUT_DOCKER_REGISTRIES=$'registry.example.com|user1|pass1\n\nother.example.com|user2|pass2'

  resolve_registries

  [ "${#REGISTRIES[@]}" -eq 2 ]
}
