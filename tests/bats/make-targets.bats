#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

stub_tools() {
  export TOOL_LOG="${BATS_TEST_TMPDIR}/tools.log"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local tool
  for tool in terraform tflint shellcheck shfmt oc bats; do
    cat >"${BATS_TEST_TMPDIR}/bin/${tool}" <<'SH'
#!/bin/bash
tool="${0##*/}"
printf '%s %s\n' "$tool" "$*" >>"${TOOL_LOG}"
if [[ "$tool $*" == "${FAIL_COMMAND:-}" || "$tool" == "${FAIL_COMMAND:-}" ]]; then
  echo "injected failure: $tool $*" >&2
  exit 42
fi
SH
    chmod +x "${BATS_TEST_TMPDIR}/bin/${tool}"
  done
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "test stops at any failing Terraform suite" {
  stub_tools
  local suite
  for suite in terraform/wif terraform; do
    : >"${TOOL_LOG}"
    export FAIL_COMMAND="terraform -chdir=${REPO_ROOT}/${suite} test"
    run make -C "${REPO_ROOT}" -o lint test
    [ "$status" -ne 0 ]
    [[ "$output" == *"injected failure:"* ]]
    [ "$(tail -n 1 "${TOOL_LOG}")" = "${FAIL_COMMAND}" ]
  done
}

@test "cluster profile must exist" {
  run make -C "$REPO_ROOT" cluster.missing.plan
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "help lists public profile example" {
  run make -C "$REPO_ROOT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"cluster.public.plan"* ]]
  [[ "$output" == *"cluster.virt.plan"* ]]
  [[ "$output" == *"bootstrap"* ]]
  [[ "$output" != *"machinesets"* ]]
}

@test "virt profile directory and tfvars exist" {
  [ -d "${REPO_ROOT}/clusters/virt" ]
  [ -f "${REPO_ROOT}/clusters/virt/terraform.tfvars" ]
  rg 'n2-standard-8' "${REPO_ROOT}/clusters/virt/terraform.tfvars"
  rg 'np-nested-lab' "${REPO_ROOT}/clusters/virt/terraform.tfvars"
  rg 'replicas\s*=\s*2' "${REPO_ROOT}/clusters/virt/terraform.tfvars"
}

@test "preflight allows TF_VAR conflict when tfvars wins on apply" {
  run bash -c 'export OSDGOOGLE_TOKEN=fake; export TFVARS="'"${REPO_ROOT}/clusters/virt/terraform.tfvars"'"; export TF_VAR_cluster_name=cz-demo; source "'"${REPO_ROOT}"'/scripts/lib.sh"; warn_stray_tf_vars; assert_gcp_project_configured'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored on apply"* ]]
}

@test "cluster-longrun refuses destroy without confirm" {
  run bash "${REPO_ROOT}/scripts/cluster-longrun.sh" virt destroy
  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing destroy"* ]]
}

@test "cluster-longrun help mentions DESTROY_CONFIRM" {
  run bash "${REPO_ROOT}/scripts/cluster-longrun.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"DESTROY_CONFIRM"* ]]
}

@test "apply rejects placeholder gcp_project_id" {
  local tmp_tfvars="${BATS_TEST_TMPDIR}/terraform.tfvars"
  printf 'cluster_name = "public"\ngcp_project_id = "replace-me"\ngcp_region = "us-central1"\nopenshift_version = "4.21.3"\n' >"${tmp_tfvars}"
  run bash -c 'export OSDGOOGLE_TOKEN=fake-token-for-test; while IFS= read -r line; do unset "${line%%=*}"; done < <(env | grep "^TF_VAR_"); make -C "'"$REPO_ROOT"'" cluster.public.apply TFVARS="'"${tmp_tfvars}"'"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"replace-me"* ]]
}
