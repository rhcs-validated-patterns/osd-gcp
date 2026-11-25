#!/usr/bin/env bash
# Shared helpers for OSD on GCP deployment scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
WIF_DIR="${ROOT_DIR}/terraform/wif"
CLUSTER="${CLUSTER:-}"
TFVARS="${TFVARS:-}"

if [[ -z "${TFVARS}" && -n "${CLUSTER}" ]]; then
  TFVARS="${ROOT_DIR}/clusters/${CLUSTER}/terraform.tfvars"
fi

if [[ -z "${TFVARS}" ]]; then
  TFVARS="${ROOT_DIR}/clusters/public/terraform.tfvars"
fi

if [[ -n "${CLUSTER:-}" ]]; then
  export TF_DATA_DIR="${ROOT_DIR}/clusters/${CLUSTER}/.terraform"
  export TF_WIF_DATA_DIR="${ROOT_DIR}/clusters/${CLUSTER}/.terraform-wif"
elif [[ -f "${TFVARS}" ]]; then
  profile_dir="$(basename "$(dirname "${TFVARS}")")"
  export TF_DATA_DIR="${ROOT_DIR}/clusters/${profile_dir}/.terraform"
  export TF_WIF_DATA_DIR="${ROOT_DIR}/clusters/${profile_dir}/.terraform-wif"
fi

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

default_kubeconfig_path() {
  if [[ -n "${CLUSTER:-}" ]]; then
    printf '%s\n' "${ROOT_DIR}/.kube/config-${CLUSTER}"
  else
    printf '%s\n' "${ROOT_DIR}/.kube/config"
  fi
}

tfvars_get() {
  local key="$1"
  [[ -f "${TFVARS}" ]] || return 1
  awk -v k="${key}" '
    $1 == k && $2 == "=" {
      val = $3
      for (i = 4; i <= NF; i++) val = val " " $i
      gsub(/^[ \t"]+|[ \t",]+$/, "", val)
      print val
      exit
    }
  ' "${TFVARS}"
}

# Match Terraform precedence for this repo: Make always passes -var-file (see TFVARS).
# CLI -var/-var-file outrank TF_VAR_* (https://developer.hashicorp.com/terraform/language/values/variables).
effective_tfvar() {
  local key="$1"
  local file_val env_name env_val
  file_val="$(tfvars_get "${key}" || true)"
  if [[ -n "${file_val}" ]]; then
    printf '%s\n' "${file_val}"
    return 0
  fi
  env_name="TF_VAR_${key}"
  env_val="${!env_name-}"
  if [[ -n "${env_val}" ]]; then
    printf '%s\n' "${env_val}"
    return 0
  fi
  printf ''
}

resolve_tf() {
  local name="$1"
  local val=""
  local terraform_bin="${TERRAFORM_BIN:-terraform}"
  val="$("${terraform_bin}" -chdir="${TF_DIR}" output -raw "${name}" 2>/dev/null || true)"
  if [[ -n "${val}" && "${val}" != "null" ]]; then
    printf '%s\n' "${val}"
    return 0
  fi
  tfvars_get "${name}"
}

tf_output_json() {
  local name="${1:-}"
  local terraform_bin="${TERRAFORM_BIN:-terraform}"
  if [[ -n "${name}" ]]; then
    "${terraform_bin}" -chdir="${TF_DIR}" output -json "${name}"
  else
    "${terraform_bin}" -chdir="${TF_DIR}" output -json
  fi
}

load_tf() {
  if [[ -n "${CLUSTER:-}" && "${CLUSTER_NAME:-}" == "${CLUSTER}" ]]; then
    unset CLUSTER_NAME
  fi

  CLUSTER_NAME="${CLUSTER_NAME:-$(resolve_tf cluster_name || true)}"
  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(resolve_tf gcp_project_id || effective_tfvar gcp_project_id || true)}"
  GCP_REGION="${GCP_REGION:-$(resolve_tf gcp_region || effective_tfvar gcp_region || true)}"
  API_URL="${API_URL:-$(resolve_tf api_url || true)}"
  CONSOLE_URL="${CONSOLE_URL:-$(resolve_tf console_url || true)}"

  : "${CLUSTER_NAME:?cluster_name required (terraform output or clusters/<name>/terraform.tfvars)}"
  : "${KUBECONFIG_PATH:=$(default_kubeconfig_path)}"
  PULL_SECRET_SECRET_NAME="${PULL_SECRET_SECRET_NAME:-$(resolve_tf pull_secret_secret_name || tfvars_get pull_secret_secret_name || true)}"
  PULL_SECRET_SECRET_NAME="${PULL_SECRET_SECRET_NAME:-redhat-pull-secret}"
  ESO_GCP_SERVICE_ACCOUNT_EMAIL="${ESO_GCP_SERVICE_ACCOUNT_EMAIL:-$(resolve_tf eso_gcp_service_account_email || true)}"
  ESO_AUTH_METHOD="${ESO_AUTH_METHOD:-$(resolve_tf eso_auth_method || true)}"
  ESO_WIF_AUDIENCE="${ESO_WIF_AUDIENCE:-$(resolve_tf wif_kubernetes_token_audience || resolve_tf eso_wif_audience || true)}"
  ESO_WIF_PRINCIPAL_MEMBER="${ESO_WIF_PRINCIPAL_MEMBER:-$(resolve_tf eso_wif_principal_member || true)}"
}

export_tf_var_pull_secret_path() {
  local p="${PULL_SECRET_PATH:-}"
  if [[ -z "${p}" ]]; then
    p="$(tfvars_get pull_secret_path || true)"
  fi
  [[ -n "${p}" ]] || return 0
  p="${p/#\~/${HOME}}"
  [[ -f "${p}" ]] || die "Missing pull secret file ${p} (pull_secret_path / PULL_SECRET_PATH)"
  TF_VAR_pull_secret_path="$(cd "$(dirname "${p}")" && pwd)/$(basename "${p}")"
  export TF_VAR_pull_secret_path
}

configure_gitops_oidc() {
  log "OSD: skipping Entra Argo CD oidcConfig (use OpenShift OAuth / cluster-admin on the GitOps route)"
}

assert_ocm_token_present() {
  if [[ -z "${OSDGOOGLE_TOKEN:-}" && -n "${OCM_TOKEN:-}" ]]; then
    export OSDGOOGLE_TOKEN="${OCM_TOKEN}"
  fi
  if [[ -n "${OSDGOOGLE_TOKEN:-}" || -n "${OSDGOOGLE_CLIENT_ID:-}" ]]; then
    return 0
  fi
  die "Set OSDGOOGLE_TOKEN (or OCM_TOKEN) or OSDGOOGLE_CLIENT_ID/OSDGOOGLE_CLIENT_SECRET before mutating applies."
}

assert_gcp_project_configured() {
  local project="${1:-$(effective_tfvar gcp_project_id || true)}"
  [[ -n "${project}" ]] || die "gcp_project_id missing (set in ${TFVARS} or TF_VAR_gcp_project_id when not in tfvars)."
  if [[ "${project}" == "replace-me" ]]; then
    die "gcp_project_id is still replace-me in ${TFVARS}. Edit tfvars before apply (-var-file wins over TF_VAR_gcp_project_id)."
  fi
}

warn_stray_tf_vars() {
  local line name key val file_val
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    name="${line%%=*}"
    val="${line#*=}"
    key="${name#TF_VAR_}"
    file_val="$(tfvars_get "${key}" || true)"
    [[ -z "${file_val}" ]] && continue
    if [[ "${file_val}" != "${val}" ]]; then
      log "Note: ${name} is set in the shell but ignored on apply; ${TFVARS} sets ${key} = ${file_val} (-var-file outranks TF_VAR_*)."
    fi
  done < <(env | grep '^TF_VAR_' || true)
}

assert_gcloud_project_matches() {
  require_cmd gcloud
  gcloud auth application-default print-access-token >/dev/null 2>&1 \
    || die "Application Default Credentials missing or expired. Run: gcloud auth application-default login"
  local expected="${1:-$(effective_tfvar gcp_project_id || true)}"
  local active
  active="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -n "${active}" && "${active}" != "${expected}" ]]; then
    log "Note: gcloud config project is ${active}; Terraform uses gcp_project_id=${expected} with ADC"
  fi
}

preflight_mutating() {
  warn_stray_tf_vars
  assert_ocm_token_present
  assert_gcp_project_configured
  assert_gcloud_project_matches
}

ensure_kubeconfig_dir() {
  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
}

export_kubeconfig_env() {
  export KUBECONFIG="${KUBECONFIG_PATH}"
}

wif_init() {
  local state_path="$1"
  TF_DATA_DIR="${TF_WIF_DATA_DIR}" terraform -chdir="${WIF_DIR}" init -reconfigure -input=false \
    -backend-config="path=${state_path}"
}

cluster_init() {
  local state_path="$1"
  terraform -chdir="${TF_DIR}" init -reconfigure -input=false \
    -backend-config="path=${state_path}"
}
