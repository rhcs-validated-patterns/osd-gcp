#!/usr/bin/env bash
# Run cluster apply/destroy under tmux (or nohup) with env and logs wired for agents/operators.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT_DIR}/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: cluster-longrun.sh <profile> <apply|destroy> [--confirm]

Runs make cluster.<profile>.<op> with stdout/stderr teed to
clusters/<profile>/logs/<utc>-<op>.log.

Destroy requires DESTROY_CONFIRM=yes in the shell or --confirm on this command
(so tmux sessions do not accidentally omit the guard).

Examples:
  DESTROY_CONFIRM=yes ./scripts/cluster-longrun.sh virt destroy
  make -f Makefile.cluster CLUSTER_PROFILE=virt longrun.apply
EOF
}

PROFILE="${1:-}"
OP="${2:-}"
CONFIRM_FLAG="${3:-}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ -n "${PROFILE}" && -n "${OP}" ]] || {
  usage
  exit 1
}
[[ "${OP}" == apply || "${OP}" == destroy ]] || die "operation must be apply or destroy"
[[ -d "${ROOT_DIR}/clusters/${PROFILE}" ]] || die "missing clusters/${PROFILE}"

if [[ "${OP}" == destroy ]]; then
  if [[ "${DESTROY_CONFIRM:-}" != "yes" && "${CONFIRM_FLAG}" != "--confirm" ]]; then
    die "Refusing destroy in tmux without DESTROY_CONFIRM=yes or --confirm"
  fi
  export DESTROY_CONFIRM=yes
fi

LOG_DIR="${ROOT_DIR}/clusters/${PROFILE}/logs"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/$(date -u +%Y%m%dT%H%MZ)-${OP}.log"
SESSION="osd-gcp-${PROFILE}-${OP}"
ENV_FILE="${LOG_DIR}/.longrun-env.$$"

{
  echo "DESTROY_CONFIRM=${DESTROY_CONFIRM:-}"
  for v in OSDGOOGLE_TOKEN OSDGOOGLE_CLIENT_ID OSDGOOGLE_CLIENT_SECRET OCM_TOKEN; do
    if [[ -n "${!v:-}" ]]; then
      printf '%s=%q\n' "${v}" "${!v}"
    fi
  done
} >"${ENV_FILE}"
chmod 600 "${ENV_FILE}"

RUNNER="${LOG_DIR}/.longrun-run-$$.sh"
cat >"${RUNNER}" <<RUN
#!/usr/bin/env bash
set -euo pipefail
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a
cd "${ROOT_DIR}"
make cluster.${PROFILE}.${OP} 2>&1 | tee "${LOG}"
echo DONE >>"${LOG}"
rm -f "${ENV_FILE}" "${RUNNER}"
RUN
chmod 700 "${RUNNER}"

if command -v tmux >/dev/null 2>&1; then
  tmux kill-session -t "${SESSION}" 2>/dev/null || true
  tmux new-session -d -s "${SESSION}" "${RUNNER}"
  log "tmux session ${SESSION}; log ${LOG}"
  log "Attach: tmux attach -t ${SESSION}"
else
  log "tmux not installed; running ${RUNNER} in background"
  nohup "${RUNNER}" >/dev/null 2>&1 &
  log "log ${LOG}"
fi
