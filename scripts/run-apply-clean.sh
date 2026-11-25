#!/usr/bin/env bash
# Run cluster apply with only OSD-relevant env (drops stray TF_VAR_* from other stacks).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  unset "${line%%=*}"
done < <(env | grep '^TF_VAR_' || true)
if [[ -z "${OSDGOOGLE_TOKEN:-}" ]]; then
  if command -v ocm >/dev/null 2>&1 && ocm whoami >/dev/null 2>&1; then
    token="$(ocm token)"
    export OSDGOOGLE_TOKEN="${token}"
    echo "Using short-lived token from 'ocm token' (long applies need an offline token in OSDGOOGLE_TOKEN)." >&2
  else
    echo "Set OSDGOOGLE_TOKEN (offline token from console.redhat.com/openshift/token) or log in with: ocm login" >&2
    exit 1
  fi
fi
mkdir -p clusters/public/logs
LOG="clusters/public/logs/$(date -u +%Y%m%dT%H%M%SZ)-apply.log"
exec make cluster.public.apply 2>&1 | tee "$LOG"
