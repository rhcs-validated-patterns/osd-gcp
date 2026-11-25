#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CLUSTER=public
  export TFVARS="${BATS_TEST_TMPDIR}/terraform.tfvars"
  export TERRAFORM_BIN="${REPO_ROOT}/tests/fixtures/terraform-output-fake.sh"
  export KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kubeconfig"
  export CALLS="${BATS_TEST_TMPDIR}/calls"
  printf 'cluster_name = "public"\n' >"$TFVARS"
  touch "$KUBECONFIG_PATH"
}

@test "bootstrap dry run includes split bootstrap resources and osd-platform-metadata" {
  export GITOPS_DRY_RUN=1 GITOPS_LOCAL_ONLY=1
  run bash "$REPO_ROOT/scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"kind: OperatorGroup"* ]]
  [[ "$output" == *"upgradeStrategy: Default"* ]]
  [[ "$output" == *"name: osd-platform-metadata"* ]]
  [[ "$output" == *"gcpProjectId:"* ]]
  [[ "$output" == *"name: web-terminal"* ]]
}

@test "normal bootstrap dry run retains the published-source Application" {
  export GITOPS_DRY_RUN=1 GITOPS_LOCAL_ONLY=0
  run bash "$REPO_ROOT/scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"kind: Application"* ]]
  [[ "$output" == *"path: gitops/overlays/public"* ]]
}

@test "local-only live path applies baseline without submitting an Application" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/oc" <<'SH'
#!/bin/bash
printf 'oc %s\n' "$*" >>"$CALLS"
case "$*" in
  'apply -f -') cat >>"$CALLS" ;;
  *'get subscription '*'-o jsonpath='*) echo fixture-csv ;;
  *'get csv '*'-o jsonpath='*) echo Succeeded ;;
  *'get secret additional-pull-secret '*|'create secret generic additional-pull-secret '*|'create secret generic eso-gcp-credentials '*|'get secret eso-gcp-credentials '*|'get argocd '*|'wait '*|'get deploy '*)
    ;;
esac
exit 0
SH
  cat >"$BATS_TEST_TMPDIR/bin/gcloud" <<'SH'
#!/bin/bash
echo '{"auths":{}}'
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/oc" "$BATS_TEST_TMPDIR/bin/gcloud"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export GITOPS_LOCAL_ONLY=1 GITOPS_WAIT_SECONDS=2
  unset GITOPS_DRY_RUN
  run bash "$REPO_ROOT/scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"deferred"* ]]
  rg 'apply -k .*gitops/overlays/public' "$CALLS"
  ! rg 'kind: Application' "$CALLS"
}
