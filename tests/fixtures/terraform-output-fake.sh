#!/usr/bin/env bash
case "$1" in
  -chdir)
    shift 2
    ;;
  -chdir=*)
    shift 1
    ;;
esac
if [ "$1" = "output" ] && [ "$2" = "-json" ]; then
  if [ "${3:-}" = "platform" ]; then
    cat <<'JSON'
{
  "contract_version": 1,
  "installer": "osd-gcp",
  "cluster_name": "public",
  "cluster_id": "00000000-0000-0000-0000-000000000001",
  "gcp_project_id": "test-project",
  "gcp_region": "us-central1",
  "wif_config_id": "00000000-0000-0000-0000-wif00000001",
  "api_url": "https://api.example:6443",
  "console_url": "https://console.example",
  "network": {
    "vpc_name": "public-network",
    "control_plane_subnet": "public-master",
    "compute_subnet": "public-worker",
    "psc_enabled": false
  },
  "default_workers": {
    "replicas": 3,
    "instance_type": "n2-standard-4"
  },
  "machine_pools": {},
  "eso": {
    "auth_method": "workload_identity_federation",
    "gcp_service_account_email": "public-eso@test-project.iam.gserviceaccount.com",
    "pull_secret_secret_name": "redhat-pull-secret",
    "pull_secret_stored": false,
    "wif_kubernetes_token_audience": "openshift",
    "wif_provider_resource_name": "projects/123/locations/global/workloadIdentityPools/pool/providers/oidc",
    "workload_identity_principal_member": "principal://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/pool/subject/system:serviceaccount:external-secrets-operator:external-secrets-sa"
  }
}
JSON
    exit 0
  fi
fi
if [ "$1" = "output" ] && [ "$2" = "-raw" ]; then
  case "${3:-}" in
    api_url) echo "https://api.example:6443" ;;
    admin_username) echo "admin" ;;
    admin_password) echo "secret" ;;
    cluster_name) echo "public" ;;
    gcp_project_id) echo "test-project" ;;
    eso_gcp_service_account_email) echo "public-eso@test-project.iam.gserviceaccount.com" ;;
    eso_auth_method) echo "workload_identity_federation" ;;
    pull_secret_secret_name) echo "redhat-pull-secret" ;;
    wif_kubernetes_token_audience) echo "openshift" ;;
    eso_wif_audience) echo "openshift" ;;
    eso_wif_sts_audience) echo "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/pool/providers/oidc" ;;
    eso_wif_provider_resource_name) echo "projects/123/locations/global/workloadIdentityPools/pool/providers/oidc" ;;
    eso_wif_principal_member) echo "principal://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/pool/subject/system:serviceaccount:external-secrets-operator:external-secrets-sa" ;;
  esac
  exit 0
fi
echo "terraform-fake: unhandled args: $*" >&2
exit 1
