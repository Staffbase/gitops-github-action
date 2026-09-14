#!/usr/bin/env bash
# Decides whether the registry steps can authenticate, and refuses to continue on
# a half-configured credential.
#
# Two sources are supported. A Google access token wins when present: Artifact
# Registry accepts it as a basic-auth password under the fixed username
# "oauth2accesstoken", both for `docker login` and for the registry v2 API the
# retag step talks to. Otherwise the action falls back to the docker-username /
# docker-password pair, which is how Harbor is reached.
#
# No credentials at all is a supported configuration, not a mistake: the
# deploy-only usage in the README passes none, and the build and push steps are
# skipped. Partial credentials are always a mistake, because they are what a
# mistyped secret name looks like, and silently skipping the build there is how a
# deployment quietly goes stale. Those fail here instead.
#
# No credential passes through this script. A password belongs in neither a step
# output nor the environment file, so action.yml selects both halves inline and
# only the decision is made here.
#
# Optional env vars: INPUT_GCP_ACCESS_TOKEN, INPUT_GCP_WORKLOAD_IDENTITY_PROVIDER,
#                    INPUT_GCP_SERVICE_ACCOUNT, INPUT_DOCKER_USERNAME,
#                    INPUT_DOCKER_PASSWORD
#
# Outputs (via GITHUB_OUTPUT): authenticated, mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

GCP_ACCESS_TOKEN="${INPUT_GCP_ACCESS_TOKEN:-}"
GCP_PROVIDER="${INPUT_GCP_WORKLOAD_IDENTITY_PROVIDER:-}"
GCP_SERVICE_ACCOUNT="${INPUT_GCP_SERVICE_ACCOUNT:-}"
DOCKER_USERNAME="${INPUT_DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${INPUT_DOCKER_PASSWORD:-}"

# --- Google, when the auth step produced a token ---

if [[ -n "$GCP_ACCESS_TOKEN" ]]; then
  log_info "Registry authentication mode: wif"
  set_output "authenticated" "true"
  set_output "mode" "wif"
  exit 0
fi

# --- Google, half-configured ---

if [[ -n "$GCP_PROVIDER" && -z "$GCP_SERVICE_ACCOUNT" ]]; then
  log_error "gcp-workload-identity-provider is set but gcp-service-account is empty. Workload Identity Federation needs both."
  exit 1
fi

if [[ -z "$GCP_PROVIDER" && -n "$GCP_SERVICE_ACCOUNT" ]]; then
  log_error "gcp-service-account is set but gcp-workload-identity-provider is empty. Workload Identity Federation needs both."
  exit 1
fi

if [[ -n "$GCP_PROVIDER" && -n "$GCP_SERVICE_ACCOUNT" ]]; then
  log_error "Workload Identity Federation is configured but no access token was produced. The calling job must grant 'permissions: id-token: write' — a composite action cannot request it for itself."
  exit 1
fi

# --- Username and password ---

if [[ -n "$DOCKER_USERNAME" && -z "$DOCKER_PASSWORD" ]]; then
  log_error "docker-username is set but docker-password is empty. Check that the password secret exists and is spelled correctly."
  exit 1
fi

if [[ -z "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  log_error "docker-password is set but docker-username is empty. Check that the username variable exists and is spelled correctly."
  exit 1
fi

if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  log_info "Registry authentication mode: basic"
  set_output "authenticated" "true"
  set_output "mode" "basic"
  exit 0
fi

# --- Nothing supplied: the deploy-only configuration ---

log_warn "No registry credentials supplied. The build and push steps will be skipped, which is expected only for the deploy-only usage. Pass docker-username and docker-password, or the gcp-* inputs, to build and push."
set_output "authenticated" "false"
set_output "mode" "none"
