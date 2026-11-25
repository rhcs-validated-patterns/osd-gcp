#!/usr/bin/env bash
# Undelete soft-deleted GCP project custom IAM roles created by osd-wif-gcp.
# Typical Terraform error: role_id (...) marked for deletion, failedPrecondition.
#
# Default mode reads gcp_project_id and role prefix from terraform/wif (same rules
# as osd-wif-config) using clusters/<profile>/terraform.tfvars (TFVARS).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF' >&2
Usage:
  gcp-undelete-wif-custom-roles.sh [--dry-run] [--continue-on-error]
  gcp-undelete-wif-custom-roles.sh PROJECT_ID ROLE_ID [ROLE_ID ...] [--dry-run] [--continue-on-error]
  gcp-undelete-wif-custom-roles.sh --from-log PATH [--dry-run] [--continue-on-error]

Default (no project/role args): Terraform in terraform/wif/ with TFVARS (or
WIF_UNDELETE_VAR_FILE), compares gcloud iam roles list with vs without
--show-deleted, undeletes matching role_ids for the WIF role prefix.

Options:
  --from-log PATH       Parse projects/PROJECT/roles/ROLE_ID from a log file.
  --terraform-dir PATH  Terraform root (default: REPO/terraform/wif).
  --no-prefix-filter    Undelete all soft-deleted custom roles in the project.
  --dry-run             Print gcloud commands only.
  --continue-on-error   Try every role; exit 1 if any undelete failed.

Examples:
  TFVARS=clusters/public/terraform.tfvars ./scripts/gcp-undelete-wif-custom-roles.sh
  make cluster.public.wif-undelete-roles
  make cluster.public.wif-undelete-roles WIF_UNDELETE_ARGS='--dry-run'
  ./scripts/gcp-undelete-wif-custom-roles.sh PROJECT public_osd_deployer_v4.21
EOF
  exit 1
}

command -v gcloud >/dev/null 2>&1 || {
  echo "Error: gcloud not found on PATH." >&2
  exit 1
}

dry_run=0
continue_on_error=0
from_log=""
no_prefix_filter=0
terraform_dir_cli=""
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --continue-on-error)
      continue_on_error=1
      shift
      ;;
    --no-prefix-filter)
      no_prefix_filter=1
      shift
      ;;
    --from-log)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --from-log requires a file path." >&2
        exit 1
      fi
      from_log="$2"
      shift 2
      ;;
    --terraform-dir)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --terraform-dir requires a directory path." >&2
        exit 1
      fi
      terraform_dir_cli="$2"
      shift 2
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

run_undelete() {
  local project_id="$1"
  local role_id="$2"
  echo "Undeleting projects/${project_id}/roles/${role_id} ..."
  if [[ "$dry_run" -eq 1 ]]; then
    echo "  (dry-run) gcloud iam roles undelete ${role_id} --project=${project_id}"
    return 0
  fi
  gcloud iam roles undelete "${role_id}" --project="${project_id}"
}

strip_tf_string() {
  sed 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/' | tr -d '\r'
}

resolve_terraform_dir() {
  if [[ -n "${terraform_dir_cli}" ]]; then
    echo "${terraform_dir_cli}"
  elif [[ -n "${WIF_UNDELETE_TERRAFORM_DIR:-}" ]]; then
    echo "${WIF_UNDELETE_TERRAFORM_DIR}"
  else
    echo "${ROOT}/terraform/wif"
  fi
}

resolve_var_file() {
  if [[ -n "${WIF_UNDELETE_VAR_FILE:-}" ]]; then
    echo "${WIF_UNDELETE_VAR_FILE}"
  elif [[ -n "${TFVARS:-}" ]]; then
    echo "${TFVARS}"
  else
    echo ""
  fi
}

terraform_var_args() {
  local vf
  vf="$(resolve_var_file)"
  if [[ -n "${vf}" ]]; then
    if [[ ! -f "${vf}" ]]; then
      echo "Error: var-file not found: ${vf}" >&2
      exit 1
    fi
    printf '%s' "-var-file=${vf}"
  fi
}

terraform_console() {
  local tf_dir="$1"
  local expr="$2"
  local var_args out err ec
  var_args="$(terraform_var_args)"
  err="$(mktemp)" || exit 1
  set +e
  # shellcheck disable=SC2086
  out="$(printf '%s\n' "${expr}" | terraform -chdir="${tf_dir}" console ${var_args} 2>"${err}")"
  ec=$?
  set -e
  if [[ "${ec}" -ne 0 ]]; then
    echo "Error: terraform console failed in ${tf_dir} for expression:" >&2
    echo "  ${expr}" >&2
    cat "${err}" >&2
    rm -f "${err}"
    exit 1
  fi
  rm -f "${err}"
  echo "${out}" | strip_tf_string
}

list_soft_deleted_full_names_to_file() {
  local project_id="$1"
  local out_file="$2"
  local active all
  active="$(mktemp)" || exit 1
  all="$(mktemp)" || exit 1
  if ! gcloud iam roles list --project="${project_id}" --format='value(name)' | sort -u >"${active}"; then
    rm -f "${active}" "${all}"
    return 1
  fi
  if ! gcloud iam roles list --project="${project_id}" --show-deleted --format='value(name)' | sort -u >"${all}"; then
    rm -f "${active}" "${all}"
    return 1
  fi
  comm -23 "${all}" "${active}" >"${out_file}"
  rm -f "${active}" "${all}"
}

auto_discover_from_terraform() {
  command -v terraform >/dev/null 2>&1 || {
    echo "Error: terraform not found on PATH (required for auto mode)." >&2
    exit 1
  }

  local tf_dir var_args
  tf_dir="$(resolve_terraform_dir)"
  var_args="$(terraform_var_args)"
  if [[ -z "${var_args}" ]]; then
    echo "Error: set TFVARS or WIF_UNDELETE_VAR_FILE to clusters/<profile>/terraform.tfvars" >&2
    exit 1
  fi
  if [[ ! -d "${tf_dir}" ]]; then
    echo "Error: Terraform directory not found: ${tf_dir}" >&2
    exit 1
  fi

  echo "=== Auto mode: Terraform in ${tf_dir} (${var_args}) ==="
  if ! terraform -chdir="${tf_dir}" init -backend=false -input=false >/dev/null; then
    echo "Error: terraform init failed in ${tf_dir}" >&2
    exit 1
  fi

  local project_id prefix
  project_id="$(terraform_console "${tf_dir}" "var.gcp_project_id")"
  if [[ -z "${project_id}" ]]; then
    echo "Error: var.gcp_project_id is empty." >&2
    exit 1
  fi

  prefix="$(terraform_console "${tf_dir}" 'coalesce(var.role_prefix, replace(replace(var.cluster_name, "-", ""), "_", ""))')"
  if [[ -z "${prefix}" ]]; then
    echo "Error: could not compute WIF role prefix from Terraform." >&2
    exit 1
  fi

  echo "GCP project: ${project_id}"
  if [[ "${no_prefix_filter}" -eq 1 ]]; then
    echo "Filter: all soft-deleted custom roles in project (--no-prefix-filter)"
  else
    echo "Role id prefix (from Terraform): ${prefix}"
  fi

  local names_tmp roles_tmp
  names_tmp="$(mktemp)" || exit 1
  roles_tmp="$(mktemp)" || exit 1
  if ! list_soft_deleted_full_names_to_file "${project_id}" "${names_tmp}"; then
    echo "Error: gcloud iam roles list failed for project ${project_id}" >&2
    rm -f "${names_tmp}" "${roles_tmp}"
    exit 1
  fi
  : >"${roles_tmp}"
  while IFS= read -r full_name || [[ -n "${full_name}" ]]; do
    [[ -z "${full_name}" ]] && continue
    rid="${full_name##*/roles/}"
    [[ -z "${rid}" || "${rid}" == "${full_name}" ]] && continue
    if [[ "${no_prefix_filter}" -eq 1 ]]; then
      echo "${rid}" >>"${roles_tmp}"
    elif [[ "${rid}" == "${prefix}"* ]]; then
      echo "${rid}" >>"${roles_tmp}"
    fi
  done <"${names_tmp}"
  sorted_tmp="$(mktemp)" || exit 1
  sort -u <"${roles_tmp}" >"${sorted_tmp}"
  mv "${sorted_tmp}" "${roles_tmp}"
  names_nonempty=0
  [[ -s "${names_tmp}" ]] && names_nonempty=1
  rm -f "${names_tmp}"

  if [[ ! -s "${roles_tmp}" ]]; then
    if [[ "${names_nonempty}" -eq 1 ]]; then
      echo "Soft-deleted role(s) were found via list diff, but none matched role_id prefix '${prefix}'."
      echo "Check cluster_name / role_prefix in terraform.tfvars vs the role_id in the Terraform error."
    elif [[ "${no_prefix_filter}" -eq 1 ]]; then
      echo "No soft-deleted custom roles found in ${project_id}. Nothing to do."
    else
      echo "No soft-deleted custom roles found in ${project_id} with prefix '${prefix}'."
      c0="$(gcloud iam roles list --project="${project_id}" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
      c1="$(gcloud iam roles list --project="${project_id}" --show-deleted --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
      echo "Diagnostic: role list lines without --show-deleted=${c0}, with --show-deleted=${c1}."
      echo "If apply still fails with \"marked for deletion\" but describe/undelete return NOT_FOUND,"
      echo "the role_id is tombstoned. Use a new cluster_name or wait for GCP to release the id."
      echo "See docs/guides/wif-iam-after-destroy.md"
    fi
    rm -f "${roles_tmp}"
    exit 0
  fi

  echo "Roles to undelete:"
  sed 's/^/  /' "${roles_tmp}"

  undelete_list="$(mktemp)" || exit 1
  cp "${roles_tmp}" "${undelete_list}"
  rm -f "${roles_tmp}"

  local abort_undelete=0
  while IFS= read -r role_id || [[ -n "${role_id}" ]]; do
    [[ -z "${role_id}" ]] && continue
    if run_undelete "${project_id}" "${role_id}"; then
      :
    else
      failures+=("projects/${project_id}/roles/${role_id}")
      if [[ "${continue_on_error}" -ne 1 ]]; then
        abort_undelete=1
        break
      fi
    fi
  done <"${undelete_list}"
  rm -f "${undelete_list}"
  if [[ "${abort_undelete}" -eq 1 ]]; then
    exit 1
  fi
}

declare -a failures=()

if [[ -n "${from_log}" ]]; then
  if [[ ${#positional[@]} -gt 0 ]]; then
    echo "Error: extra arguments with --from-log are not allowed." >&2
    exit 1
  fi
  if [[ ! -f "${from_log}" ]]; then
    echo "Error: log file not found: ${from_log}" >&2
    exit 1
  fi
  lines_tmp="$(mktemp)" || exit 1
  trap 'rm -f "${lines_tmp}"' EXIT
  grep -hoE 'projects/[^/[:space:]]+/roles/[^[:space:]:]+' "${from_log}" | sort -u >"${lines_tmp}" || true
  if [[ ! -s "${lines_tmp}" ]]; then
    echo "Error: no projects/PROJECT/roles/ROLE_ID matches in ${from_log}" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    project_id="${line#projects/}"
    project_id="${project_id%%/roles/*}"
    role_id="${line##*/roles/}"
    if [[ -z "${project_id}" || -z "${role_id}" || "${project_id}" == "${line}" ]]; then
      echo "Warning: could not parse: ${line}" >&2
      failures+=("${line}")
      [[ "${continue_on_error}" -eq 1 ]] || exit 1
      continue
    fi
    if run_undelete "${project_id}" "${role_id}"; then
      :
    else
      failures+=("projects/${project_id}/roles/${role_id}")
      if [[ "${continue_on_error}" -ne 1 ]]; then
        exit 1
      fi
    fi
  done <"${lines_tmp}"
  rm -f "${lines_tmp}"
  trap - EXIT
elif [[ ${#positional[@]} -ge 2 ]]; then
  project_id="${positional[0]}"
  for ((i = 1; i < ${#positional[@]}; i++)); do
    role_id="${positional[$i]}"
    if run_undelete "${project_id}" "${role_id}"; then
      :
    else
      failures+=("projects/${project_id}/roles/${role_id}")
      if [[ "${continue_on_error}" -ne 1 ]]; then
        exit 1
      fi
    fi
  done
elif [[ ${#positional[@]} -eq 1 ]]; then
  echo "Error: manual mode needs PROJECT_ID and at least one ROLE_ID." >&2
  exit 1
else
  auto_discover_from_terraform
fi

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "The following undelete operations failed:" >&2
  printf '  %s\n' "${failures[@]}" >&2
  exit 1
fi

echo
echo "Done. Re-run make cluster.<profile>.apply. If Terraform still wants to create roles,"
echo "import or refresh state for module.cluster.module.wif_gcp resources as needed."
