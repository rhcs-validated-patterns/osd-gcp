#!/usr/bin/env bash
# Bootstrap OpenShift GitOps and plant the root Argo Application (OSD on GCP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

GITOPS_DIR="${ROOT_DIR}/gitops"
GITOPS_REPO="${GITOPS_REPO:-https://github.com/rh-mobb/validated-pattern-osd-gcp.git}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
GITOPS_SOURCE_ROOT="${GITOPS_SOURCE_ROOT:-gitops/overlays}"
GITOPS_WAIT_SECONDS="${GITOPS_WAIT_SECONDS:-900}"
GITOPS_LOCAL_ONLY="${GITOPS_LOCAL_ONLY:-0}"
[[ "$GITOPS_LOCAL_ONLY" == 0 || "$GITOPS_LOCAL_ONLY" == 1 ]] || die "GITOPS_LOCAL_ONLY must be 0 or 1"

PLATFORM_METADATA_NS="${PLATFORM_METADATA_NS:-openshift-gitops}"
PLATFORM_METADATA_NAME="${PLATFORM_METADATA_NAME:-osd-platform-metadata}"
PULL_SECRET_TMP=""

cleanup_pull_secret_tmp() {
  if [[ -n "${PULL_SECRET_TMP:-}" && -f "${PULL_SECRET_TMP}" ]]; then
    rm -f "${PULL_SECRET_TMP}"
  fi
}
trap cleanup_pull_secret_tmp EXIT

overlay_name() {
  if [[ -n "${GITOPS_OVERLAY:-}" ]]; then
    printf '%s\n' "${GITOPS_OVERLAY}"
    return
  fi
  if [[ -n "${CLUSTER:-}" && -d "${GITOPS_DIR}/overlays/${CLUSTER}" ]]; then
    printf '%s\n' "${CLUSTER}"
    return
  fi
  printf '%s\n' public
}

kustomize_build() {
  local path="$1"
  if command -v oc >/dev/null 2>&1; then
    oc kustomize "${path}"
  elif command -v kubectl >/dev/null 2>&1; then
    kubectl kustomize "${path}"
  else
    die "oc or kubectl is required to build Kustomize (gitops/)"
  fi
}

overlay_git_path() {
  local overlay="${1:?overlay name required}"
  printf '%s/%s\n' "${GITOPS_SOURCE_ROOT}" "${overlay}"
}

render_root_application() {
  local overlay="$1"
  local src="${GITOPS_DIR}/argocd/root-application.yaml"
  awk -v repo="${GITOPS_REPO}" -v rev="${GITOPS_REVISION}" -v gpath="$(overlay_git_path "${overlay}")" '
    $1 == "repoURL:" { printf "    repoURL: %s\n", repo; next }
    $1 == "targetRevision:" { printf "    targetRevision: %s\n", rev; next }
    $1 == "path:" { printf "    path: %s\n", gpath; next }
    { print }
  ' "${src}"
}

assert_api_reachable() {
  export KUBECONFIG="${KUBECONFIG_PATH}"
  oc whoami >/dev/null 2>&1 || die "Cannot reach the cluster API (oc whoami failed). Run make cluster.${CLUSTER:-<profile>}.login first."
}

gcloud_secret_payload() {
  local project="$1"
  local secret_id="$2"
  require_cmd gcloud
  gcloud secrets versions access latest --secret="${secret_id}" --project="${project}"
}

resolve_pull_secret_file() {
  local src="${PULL_SECRET_PATH:-}"
  src="${src/#\~/${HOME}}"
  PULL_SECRET_FILE=""
  PULL_SECRET_SOURCE=""
  if [[ -n "${src}" ]]; then
    [[ -f "${src}" ]] || die "PULL_SECRET_PATH=${src} does not exist"
    PULL_SECRET_FILE="${src}"
    PULL_SECRET_SOURCE="${src}"
    return 0
  fi

  local project secret_name tmp
  project="${GCP_PROJECT_ID:-$(resolve_tf gcp_project_id || effective_tfvar gcp_project_id || true)}"
  secret_name="${PULL_SECRET_SECRET_NAME:-$(resolve_tf pull_secret_secret_name || true)}"
  secret_name="${secret_name:-redhat-pull-secret}"
  [[ -n "${project}" && "${project}" != "null" ]] || die "gcp_project_id missing; cannot read pull secret from Secret Manager."
  tmp="$(mktemp)"
  if ! gcloud_secret_payload "${project}" "${secret_name}" >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    die "OperatorHub needs kube-system/additional-pull-secret. Set pull_secret_path in tfvars and re-apply, or pass PULL_SECRET_PATH to bootstrap."
  fi
  if [[ ! -s "${tmp}" ]]; then
    rm -f "${tmp}"
    die "Secret Manager ${project}/${secret_name} is empty. Set pull_secret_path and re-apply."
  fi
  PULL_SECRET_TMP="${tmp}"
  PULL_SECRET_FILE="${tmp}"
  PULL_SECRET_SOURCE="Secret Manager ${project}/${secret_name}"
}

ensure_additional_pull_secret() {
  if oc get secret additional-pull-secret -n kube-system >/dev/null 2>&1; then
    log "kube-system/additional-pull-secret already present"
    return 0
  fi
  resolve_pull_secret_file
  log "Applying kube-system/additional-pull-secret from ${PULL_SECRET_SOURCE}"
  oc create secret generic additional-pull-secret \
    -n kube-system \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=".dockerconfigjson=${PULL_SECRET_FILE}" \
    --dry-run=client -o yaml | oc apply -f -
}

cmd_ensure_pull_secret() {
  require_cmd oc
  load_tf
  export KUBECONFIG="${KUBECONFIG_PATH}"
  ensure_additional_pull_secret
}

ensure_eso_wif_ready() {
  local audience principal
  audience="$(resolve_tf wif_kubernetes_token_audience || resolve_tf eso_wif_audience || true)"
  audience="${audience:-openshift}"
  principal="$(resolve_tf eso_wif_principal_member || true)"
  [[ -n "${principal}" && "${principal}" != "null" ]] \
    || die "eso_wif_principal_member missing; re-run make cluster.${CLUSTER:-<profile>}.apply"
  log "ESO GCP auth: OCM WIF (token audience=${audience}); impersonation ${principal}"
}

wait_for_csv_succeeded() {
  local ns="$1"
  local sub="$2"
  local deadline=$((SECONDS + GITOPS_WAIT_SECONDS))
  local csv=""
  log "Waiting for Subscription ${ns}/${sub} CSV to Succeeded (timeout ${GITOPS_WAIT_SECONDS}s)"
  while ((SECONDS < deadline)); do
    csv="$(oc get subscription "${sub}" -n "${ns}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    if [[ -n "${csv}" ]]; then
      local phase
      phase="$(oc get csv "${csv}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [[ "${phase}" == "Succeeded" ]]; then
        log "CSV ${csv} Succeeded"
        return 0
      fi
      if [[ "${phase}" == "Failed" ]]; then
        local reason msg
        reason="$(oc get csv "${csv}" -n "${ns}" -o jsonpath='{.status.reason}' 2>/dev/null || true)"
        msg="$(oc get csv "${csv}" -n "${ns}" -o jsonpath='{.status.message}' 2>/dev/null || true)"
        die "CSV ${csv} Failed (${reason}): ${msg}"
      fi
    fi
    sleep 10
  done
  die "Timed out waiting for ${ns}/${sub} CSV Succeeded"
}

wait_for_day2_operators() {
  wait_for_csv_succeeded openshift-operators web-terminal
  wait_for_csv_succeeded openshift-compliance compliance-operator
  wait_for_csv_succeeded external-secrets-operator openshift-external-secrets-operator
}

render_platform_metadata() {
  local cluster project eso_email pull_name k8s_audience sts_audience wif_provider
  cluster="$(resolve_tf cluster_name || true)"
  project="$(resolve_tf gcp_project_id || effective_tfvar gcp_project_id || true)"
  eso_email="$(resolve_tf eso_gcp_service_account_email || true)"
  pull_name="$(resolve_tf pull_secret_secret_name || true)"
  pull_name="${pull_name:-redhat-pull-secret}"
  k8s_audience="$(resolve_tf wif_kubernetes_token_audience || resolve_tf eso_wif_audience || true)"
  k8s_audience="${k8s_audience:-openshift}"
  sts_audience="$(resolve_tf eso_wif_sts_audience || true)"
  wif_provider="$(resolve_tf eso_wif_provider_resource_name || true)"

  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${PLATFORM_METADATA_NAME}
  namespace: ${PLATFORM_METADATA_NS}
  labels:
    app.kubernetes.io/name: osd-platform-metadata
data:
  clusterName: ${cluster}
  gcpProjectId: ${project}
  esoGcpServiceAccountEmail: ${eso_email}
  esoAuthMethod: workloadIdentityFederation
  pullSecretSecretName: ${pull_name}
  esoWifKubernetesTokenAudience: ${k8s_audience}
  esoWifStsAudience: ${sts_audience}
  esoWifProviderResourceName: ${wif_provider}
EOF
}

publish_platform_metadata() {
  local email
  email="$(resolve_tf eso_gcp_service_account_email || true)"
  if [[ -z "${email}" || "${email}" == "null" ]]; then
    die "terraform output eso_gcp_service_account_email is empty. Re-run make cluster.${CLUSTER:-<profile>}.apply, then bootstrap."
  fi
  log "Publishing ${PLATFORM_METADATA_NS}/${PLATFORM_METADATA_NAME}"
  render_platform_metadata | oc apply -f -
}

wait_for_argocd() {
  local deadline=$((SECONDS + GITOPS_WAIT_SECONDS))
  log "Waiting for Argo CD instance openshift-gitops"
  while ((SECONDS < deadline)); do
    if oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; then
      if oc get deploy openshift-gitops-server -n openshift-gitops >/dev/null 2>&1; then
        oc wait --for=condition=available deploy/openshift-gitops-server \
          -n openshift-gitops --timeout=60s >/dev/null 2>&1 && return 0
      fi
    fi
    sleep 10
  done
  die "Timed out waiting for Argo CD (openshift-gitops) to be available"
}

cmd_bootstrap() {
  if [[ "${GITOPS_DRY_RUN:-}" != "1" ]]; then
    require_cmd oc
    load_tf
    export KUBECONFIG="${KUBECONFIG_PATH}"
    [[ -f "${KUBECONFIG_PATH}" ]] || die "Missing ${KUBECONFIG_PATH}. Run make cluster.${CLUSTER:-<profile>}.login"
  fi

  local overlay
  overlay="$(overlay_name)"
  local overlay_dir="${GITOPS_DIR}/overlays/${overlay}"
  [[ -d "${overlay_dir}" ]] || die "Unknown GitOps overlay '${overlay}' (expected ${overlay_dir})"

  if [[ "${GITOPS_DRY_RUN:-}" == "1" ]]; then
    kustomize_build "${GITOPS_DIR}/bootstrap"
    echo "---"
    kustomize_build "${overlay_dir}"
    echo "---"
    render_platform_metadata
    echo "---"
    if [[ "$GITOPS_LOCAL_ONLY" != 1 ]]; then
      render_root_application "${overlay}"
    else
      echo "# Local baseline only; root Argo Application deferred until a Git source is published."
    fi
    echo "---"
    echo "# OSD: Argo CD uses OpenShift OAuth (no Entra oidcConfig in git)"
    return 0
  fi

  assert_api_reachable
  ensure_additional_pull_secret
  oc delete pods -n openshift-marketplace --field-selector=status.phase=Pending --ignore-not-found >/dev/null 2>&1 || true

  log "Applying GitOps operator (gitops/bootstrap)"
  oc apply -k "${GITOPS_DIR}/bootstrap"
  wait_for_csv_succeeded openshift-gitops-operator openshift-gitops-operator
  wait_for_argocd

  publish_platform_metadata
  if ! oc get namespace external-secrets-operator >/dev/null 2>&1; then
    log "Creating namespace external-secrets-operator (before day-2 operators)"
    oc apply -f "${GITOPS_DIR}/operators/external-secrets/namespace.yaml"
  fi
  ensure_eso_wif_ready

  log "Applying overlay gitops/overlays/${overlay}"
  oc delete job eso-from-metadata -n external-secrets-operator --ignore-not-found >/dev/null 2>&1 || true
  oc apply -k "${overlay_dir}"
  wait_for_day2_operators

  if [[ "$GITOPS_LOCAL_ONLY" == 1 ]]; then
    log "Local baseline applied; root Argo Application deferred until a Git source is published."
  else
    log "Planting root Application (repo=${GITOPS_REPO} revision=${GITOPS_REVISION} path=$(overlay_git_path "${overlay}"))"
    render_root_application "${overlay}" | oc apply -f -
  fi

  configure_gitops_oidc

  if [[ "$GITOPS_LOCAL_ONLY" == 1 ]]; then
    log "Local bootstrap complete; continuous Git reconciliation is not configured."
  else
    log "GitOps bootstrap complete. Argo CD syncs $(overlay_git_path "${overlay}") (prune=false)."
  fi
  log "Do not install these operators again from Software Catalog (subscriptions are managed in gitops/base)."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [bootstrap|ensure-pull-secret]

Environment:
  CLUSTER              Profile directory under clusters/
  GITOPS_OVERLAY       Overlay name (default: profile name or public)
  GITOPS_REPO          Git URL (default: rh-mobb/validated-pattern-osd-gcp)
  GITOPS_REVISION      Branch/tag/commit (default: main)
  GITOPS_DRY_RUN=1     Print Kustomize, platform metadata and optional Application YAML
  GITOPS_LOCAL_ONLY=1  Skip root Argo Application until Git source is published
  KUBECONFIG_PATH      Default: .kube/config-<profile>
  PULL_SECRET_PATH     dockerconfigjson file (overrides Secret Manager)
EOF
}

main() {
  local cmd="${1:-bootstrap}"
  case "${cmd}" in
    bootstrap) cmd_bootstrap ;;
    ensure-pull-secret) cmd_ensure_pull_secret ;;
    -h | --help | help) usage ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
