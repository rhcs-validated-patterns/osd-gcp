# Cluster profiles

| Profile | Purpose |
|---------|---------|
| [`public/`](public/) | Basic **public** OSD cluster (BYO VPC, `enable_psc = false`) |

Committed example tfvars for `make cluster.*`. Set `gcp_project_id` in the profile tfvars file (`-var-file` wins over shell `TF_VAR_*` for keys defined there).
