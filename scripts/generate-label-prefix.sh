#!/usr/bin/env bash
# Computes the reverse-DNS key prefix for deployment-tracking image labels,
# derived from the deployment domain (deploy.staffbase.com -> com.staffbase.deploy).
# Emitted as the `label_prefix` output and consumed by the Build step's image
# `labels` input. The matching GitOps annotations use the forward "<domain>/..."
# form instead (see scripts/lib/gitops-functions.sh).
#
# Optional env vars: INPUT_DEPLOYMENT_DOMAIN (defaults to "deploy.staffbase.com")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

set_output "label_prefix" "$(reverse_domain "${INPUT_DEPLOYMENT_DOMAIN:-deploy.staffbase.com}")"
