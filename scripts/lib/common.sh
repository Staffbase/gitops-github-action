#!/usr/bin/env bash
# Common utility functions for all scripts in this action.
# Sourced by other scripts — not executed directly.

set -euo pipefail

# --- Logging ---

log_info() {
  echo "::notice::$1"
}

log_warn() {
  echo "::warning::$1"
}

log_error() {
  echo "::error::$1" >&2
}

# --- Output ---

set_output() {
  local name="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  else
    echo "OUTPUT ${name}=${value}"
  fi
}

# --- Validation ---

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    log_error "Required environment variable '${var_name}' is not set or empty."
    exit 1
  fi
}

require_tool() {
  local tool_name="$1"
  if ! command -v "$tool_name" &>/dev/null; then
    log_error "Required tool '${tool_name}' is not installed or not on PATH."
    exit 1
  fi
}

# --- Retry ---

retry_with_backoff() {
  local max_attempts="$1"
  local base_delay="$2"
  shift 2
  local attempt=1
  local delay="$base_delay"

  while true; do
    if "$@"; then
      return 0
    fi

    if (( attempt >= max_attempts )); then
      log_error "Command failed after ${max_attempts} attempts: $*"
      return 1
    fi

    log_warn "Attempt ${attempt}/${max_attempts} failed. Retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}
