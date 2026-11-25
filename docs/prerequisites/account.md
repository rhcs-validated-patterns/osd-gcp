# Account prerequisites

## Red Hat / OCM

- OSD entitlement on your Red Hat account
- OCM offline token from [console.redhat.com/openshift/token](https://console.redhat.com/openshift/token)
- Export `OSDGOOGLE_TOKEN` (do **not** commit tokens to tfvars)

Optional CI automation: `OSDGOOGLE_CLIENT_ID` and `OSDGOOGLE_CLIENT_SECRET`.

## Google Cloud

- GCP project with billing enabled
- `gcloud auth login` and `gcloud auth application-default login`
- `gcloud config set project <your-project>` matching `gcp_project_id` in tfvars

## Workstation tools

```bash
make setup
```

Requires `gcloud`, `terraform`, `oc`, and `jq`.

## Experimental provider

The [rh-mobb/osd-google](https://github.com/rh-mobb/terraform-provider-osd-google) provider is maintained by MOBB and is **not** a supported Red Hat product. Pin versions as documented in [Architecture](../architecture.md).
