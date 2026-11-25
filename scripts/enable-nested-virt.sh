#!/usr/bin/env bash
# Lab-only: enable GCE nested virtualization on worker VM instances (not bare metal).
#
# This toggles advancedMachineFeatures.enableNestedVirtualization via the Compute API,
# matching osd-gcp-cudn-routing/operator/internal/gcp/compute.go (requires instance RESTART).
#
# NOT supported by Red Hat for OSD-GCP. NOT a substitute for OpenShift Virtualization on
# bare metal (c3-standard-192-metal). Use for nested KVM experiments on regular GCE workers.
#
# Usage:
#   CLUSTER=public make cluster.public.login   # or KUBECONFIG set
#   ./scripts/enable-nested-virt.sh
#   ./scripts/enable-nested-virt.sh --node my-worker-a-xyz
#   ./scripts/enable-nested-virt.sh --label workload=nested-lab
#   ./scripts/enable-nested-virt.sh --disable
#   ./scripts/enable-nested-virt.sh --dry-run
#
# Env: GCP_PROJECT (default from tfvars gcp_project_id), KUBECONFIG, CLUSTER / TFVARS (see lib.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

DRY_RUN=false
DISABLE=false
NODE_NAME=""
LABEL_SELECTOR="node-role.kubernetes.io/worker="

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage 0 ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --disable)
      DISABLE=true
      shift
      ;;
    --node)
      NODE_NAME="${2:?--node requires a name}"
      shift 2
      ;;
    --label)
      LABEL_SELECTOR="${2:?--label requires key=value or key}"
      shift 2
      ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

require_cmd oc
require_cmd gcloud
require_cmd jq

KUBECONFIG_PATH="${KUBECONFIG:-$(default_kubeconfig_path)}"
export KUBECONFIG="${KUBECONFIG_PATH}"
[[ -f "${KUBECONFIG}" ]] || die "kubeconfig not found: ${KUBECONFIG} (run make cluster.<profile>.login)"

GCP_PROJECT="${GCP_PROJECT:-$(effective_tfvar gcp_project_id)}"
[[ -n "${GCP_PROJECT}" && "${GCP_PROJECT}" != "replace-me" ]] || die "set GCP_PROJECT or gcp_project_id in ${TFVARS}"

parse_gce_provider_id() {
  local pid="$1"
  # gce://PROJECT/ZONE/INSTANCE or gce:///projects/PROJECT/zones/ZONE/instances/NAME (variants)
  if [[ "${pid}" =~ ^gce://([^/]+)/([^/]+)/(.+)$ ]]; then
    GCE_PROJECT="${BASH_REMATCH[1]}"
    GCE_ZONE="${BASH_REMATCH[2]}"
    GCE_INSTANCE="${BASH_REMATCH[3]}"
    return 0
  fi
  if [[ "${pid}" =~ zones/([^/]+)/instances/([^/]+) ]]; then
    GCE_ZONE="${BASH_REMATCH[1]}"
    GCE_INSTANCE="${BASH_REMATCH[2]}"
    GCE_PROJECT="${GCP_PROJECT}"
    return 0
  fi
  return 1
}

gce_instance_from_node() {
  local node="$1"
  local pid machine ns
  pid="$(oc get node "${node}" -o jsonpath='{.spec.providerID}' 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    machine="$(oc get node "${node}" -o jsonpath='{.metadata.annotations.machine\.openshift\.io/machine}' 2>/dev/null || true)"
    if [[ -n "${machine}" ]]; then
      ns="${machine%%/*}"
      local name="${machine##*/}"
      pid="$(oc get machine -n "${ns}" "${name}" -o jsonpath='{.spec.providerID}' 2>/dev/null || true)"
    fi
  fi
  [[ -n "${pid}" ]] || return 1
  parse_gce_provider_id "${pid}"
}

nested_enabled_on_instance() {
  local zone="$1" inst="$2"
  gcloud compute instances describe "${inst}" \
    --project="${GCE_PROJECT}" \
    --zone="${zone}" \
    --format='get(advancedMachineFeatures.enableNestedVirtualization)' 2>/dev/null | grep -q '^True$'
}

set_nested_virt() {
  local zone="$1" inst="$2" want="$3"
  local current="false"
  if nested_enabled_on_instance "${zone}" "${inst}"; then
    current="true"
  fi
  if [[ "${want}" == "${current}" ]]; then
    log "skip ${inst} (${zone}): nested virt already ${current}"
    return 0
  fi
  local flag="--enable-nested-virtualization"
  [[ "${want}" == "true" ]] || flag="--no-enable-nested-virtualization"
  log "update ${inst} in ${zone} ${flag} (instance RESTART)"
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  gcloud compute instances update "${inst}" \
    --project="${GCE_PROJECT}" \
    --zone="${zone}" \
    ${flag}
}

mapfile -t NODES < <(
  if [[ -n "${NODE_NAME}" ]]; then
    echo "${NODE_NAME}"
  else
    oc get nodes -l "${LABEL_SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  fi
)

[[ ${#NODES[@]} -gt 0 ]] || die "no nodes matched (label=${LABEL_SELECTOR}, node=${NODE_NAME})"

WANT="true"
[[ "${DISABLE}" == true ]] && WANT="false"

for node in "${NODES[@]}"; do
  [[ -n "${node}" ]] || continue
  if ! gce_instance_from_node "${node}"; then
    log "WARN: node ${node}: no GCE providerID (skip)"
    continue
  fi
  itype="$(oc get node "${node}" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}' 2>/dev/null || true)"
  if [[ "${itype}" == *metal* ]]; then
    log "WARN: node ${node} is ${itype} (bare metal host — nested GCE flag N/A; skip)"
    continue
  fi
  set_nested_virt "${GCE_ZONE}" "${GCE_INSTANCE}" "${WANT}"
done

log "done (nodes may be NotReady until instances finish restarting)"
