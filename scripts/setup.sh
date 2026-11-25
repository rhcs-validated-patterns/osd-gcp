#!/usr/bin/env bash
set -euo pipefail

missing=0
for cmd in gcloud terraform oc jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    missing=1
  fi
done

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "Warning: Application Default Credentials missing. Run: gcloud auth application-default login" >&2
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "Tooling OK for OSD on GCP."
