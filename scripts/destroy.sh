#!/usr/bin/env bash
set -euo pipefail

: "${TFVARS:?Set TFVARS}"
: "${CLUSTER_PROFILE:?Set CLUSTER_PROFILE}"

if [ "${DESTROY_CONFIRM:-}" != "yes" ]; then
  echo "Refusing destroy: set DESTROY_CONFIRM=yes" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"

CLUSTER_DIR="$(dirname "$TFVARS")"
INFRA_STATE="${CLUSTER_DIR}/infrastructure.tfstate"
WIF_STATE="${CLUSTER_DIR}/wif.tfstate"

preflight_mutating

log "Destroying cluster stack (phase 2)..."
cluster_init "${INFRA_STATE}"
terraform -chdir="${ROOT_DIR}/terraform" destroy -var-file="${TFVARS}" -auto-approve

log "Destroying WIF config (phase 1)..."
wif_init "${WIF_STATE}"
TF_DATA_DIR="${TF_WIF_DATA_DIR}" terraform -chdir="${ROOT_DIR}/terraform/wif" destroy -var-file="${TFVARS}" -auto-approve

log "Destroy complete for ${CLUSTER_PROFILE}."
