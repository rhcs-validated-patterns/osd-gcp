#!/usr/bin/env bash
# Cluster admin credentials from Terraform outputs (HTPasswd IDP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <request|show|login>

  request  Write admin kubeconfig to KUBECONFIG_PATH (default: .kube/config-<profile>)
  show     Print API/console URLs and admin username/password
  login    oc login as cluster admin (uses KUBECONFIG_PATH)
EOF
}

read_admin_credentials() {
  local terraform_bin="${TERRAFORM_BIN:-terraform}"
  API_URL="$("${terraform_bin}" -chdir="${TF_DIR}" output -raw api_url)"
  ADMIN_USERNAME="$("${terraform_bin}" -chdir="${TF_DIR}" output -raw admin_username)"
  ADMIN_PASSWORD="$("${terraform_bin}" -chdir="${TF_DIR}" output -raw admin_password)"
  [[ -n "${API_URL}" && "${API_URL}" != "null" ]] || die "api_url missing; run apply first"
  [[ -n "${ADMIN_USERNAME}" && "${ADMIN_USERNAME}" != "null" ]] || die "admin_username missing; set create_admin=true and re-apply"
  [[ -n "${ADMIN_PASSWORD}" && "${ADMIN_PASSWORD}" != "null" ]] || die "admin_password missing; re-apply with create_admin=true"
}

cmd_request() {
  load_tf
  read_admin_credentials
  ensure_kubeconfig_dir
  oc login "${API_URL}" \
    --username="${ADMIN_USERNAME}" \
    --password="${ADMIN_PASSWORD}" \
    --insecure-skip-tls-verify=true \
    --kubeconfig="${KUBECONFIG_PATH}"
  log "Kubeconfig written to ${KUBECONFIG_PATH}"
}

cmd_show() {
  load_tf
  read_admin_credentials
  echo "Cluster: ${CLUSTER_NAME}"
  echo "GCP project: ${GCP_PROJECT_ID:-$(tfvars_get gcp_project_id)}"
  echo "Region: ${GCP_REGION:-$(tfvars_get gcp_region)}"
  echo "API URL: ${API_URL}"
  echo "Console URL: ${CONSOLE_URL:-$(terraform -chdir="${TF_DIR}" output -raw console_url 2>/dev/null || echo unknown)}"
  echo ""
  echo "Username: ${ADMIN_USERNAME}"
  echo "Password: ${ADMIN_PASSWORD}"
  echo ""
  local profile="${CLUSTER:-$(basename "$(dirname "${TFVARS}")")}"
  echo "To login, run: make cluster.${profile}.login"
}

cmd_login() {
  load_tf
  read_admin_credentials
  ensure_kubeconfig_dir
  log "Logging in as ${ADMIN_USERNAME}..."
  oc login "${API_URL}" \
    --username="${ADMIN_USERNAME}" \
    --password="${ADMIN_PASSWORD}" \
    --insecure-skip-tls-verify=true \
    --kubeconfig="${KUBECONFIG_PATH}"
  export_kubeconfig_env
  log "Logged in; KUBECONFIG=${KUBECONFIG_PATH}"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    request) cmd_request ;;
    show) cmd_show ;;
    login) cmd_login ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
