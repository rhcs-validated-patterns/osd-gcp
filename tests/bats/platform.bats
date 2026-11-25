#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CLUSTER_PROFILE=public
  export CLUSTER=public
  export TFVARS="${BATS_TEST_TMPDIR}/terraform.tfvars"
  touch "${TFVARS}"
  export TERRAFORM_BIN="${REPO_ROOT}/tests/fixtures/terraform-output-fake.sh"
  export PLATFORM_FILE="${BATS_TEST_TMPDIR}/platform.json"
}

@test "platform.json uses contract_version 1 for osd-gcp" {
  run bash "${REPO_ROOT}/scripts/platform.sh"
  [ "$status" -eq 0 ]
  jq -e '.contract_version == 1' "${TFVARS%/*}/platform.json"
  jq -e '.installer == "osd-gcp"' "${TFVARS%/*}/platform.json"
  jq -e '.wif_config_id != ""' "${TFVARS%/*}/platform.json"
}
