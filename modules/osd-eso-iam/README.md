# osd-eso-iam

GCP service account and **OCM WIF pool** impersonation binding for External Secrets Operator on OSD GCP.

Mirrors [`osd-gcp-cudn-routing/modules/osd-bgp-controller-iam`](https://github.com/rh-mobb/osd-gcp-cudn-routing): `principal://…/subject/system:serviceaccount:<ns>:<ksa>` on the cluster’s existing workload identity pool from `osdgoogle_wif_config`, not a separate OIDC issuer or JSON keys.

Secret Manager access uses `roles/secretmanager.secretAccessor` on the pull secret (granted in root `platform_secrets.tf`).
