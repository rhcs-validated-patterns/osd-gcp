SHELL := /bin/bash
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TF_DIR := $(ROOT_DIR)/terraform
WIF_DIR := $(ROOT_DIR)/terraform/wif
SCRIPTS := $(ROOT_DIR)/scripts

TF_VARS_TO_UNSET := TF_VAR_cluster_name TF_VAR_gcp_project_id TF_VAR_gcp_region \
	TF_VAR_openshift_version TF_VAR_enable_psc TF_VAR_compute_nodes \
	TF_VAR_compute_machine_type TF_VAR_create_admin TF_VAR_admin_password \
	TF_VAR_machine_pools TF_VAR_ocm_token TF_VAR_role_prefix \
	TF_VAR_pull_secret_path TF_VAR_pull_secret TF_VAR_pull_secret_secret_name

.PHONY: help fmt lint test setup docs-venv docs-preview docs-build cluster.%

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "Cluster operations: make cluster.<name>.<operation>"
	@echo "  init plan apply destroy longrun.apply longrun.destroy wif.plan wif.apply wif-undelete-roles kubeconfig show-credentials login bootstrap platform"
	@echo "Examples:"
	@echo "  make cluster.public.plan"
	@echo "  make cluster.public.apply"
	@echo "  make cluster.virt.plan    # nested-lab pool (n2-standard-8)"

cluster.%:
	@CLUSTER_PROFILE=$$(echo "$@" | cut -d'.' -f2); \
	OPERATION=$$(echo "$@" | cut -d'.' -f3-); \
	if [ -z "$$CLUSTER_PROFILE" ] || [ -z "$$OPERATION" ]; then \
		echo "Usage: make cluster.<name>.<operation>" >&2; \
		exit 1; \
	fi; \
	if [ ! -d "$(ROOT_DIR)/clusters/$$CLUSTER_PROFILE" ]; then \
		echo "Cluster directory clusters/$$CLUSTER_PROFILE does not exist" >&2; \
		ls -1 "$(ROOT_DIR)/clusters/" 2>/dev/null | sed 's/^/  - /' || true; \
		exit 1; \
	fi; \
	$(MAKE) -f Makefile.cluster CLUSTER_PROFILE=$$CLUSTER_PROFILE $$OPERATION

fmt: ## Format Terraform and shell scripts
	terraform -chdir=$(TF_DIR) fmt -recursive
	terraform -chdir=$(WIF_DIR) fmt
	@if command -v shfmt >/dev/null; then shfmt -w -i 2 -ci -bn $(SCRIPTS); else echo "shfmt not installed; skipping"; fi

lint: ## Run linters (terraform validate/tflint, shellcheck)
	terraform -chdir=$(WIF_DIR) init -backend=false -input=false
	terraform -chdir=$(WIF_DIR) validate
	terraform -chdir=$(TF_DIR) init -backend=false -input=false
	terraform -chdir=$(TF_DIR) validate
	@if command -v tflint >/dev/null; then (cd $(TF_DIR) && tflint --init && tflint); else echo "tflint not installed; skipping"; fi
	@if command -v tflint >/dev/null; then (cd $(WIF_DIR) && tflint --init && tflint); else true; fi
	@if command -v shellcheck >/dev/null; then shellcheck --external-sources --source-path=$(SCRIPTS) $(SCRIPTS)/*.sh; else echo "shellcheck not installed; skipping"; fi
	@if command -v shfmt >/dev/null; then shfmt -d -i 2 -ci -bn $(SCRIPTS); else echo "shfmt not installed; skipping"; fi

test: lint ## Run unit tests (terraform test + bats)
	set -e; unset $(TF_VARS_TO_UNSET); \
	terraform -chdir=$(WIF_DIR) test; \
	terraform -chdir=$(TF_DIR) test
	@if command -v oc >/dev/null 2>&1; then \
		oc kustomize $(ROOT_DIR)/gitops/overlays/public >/dev/null; \
	elif command -v kubectl >/dev/null 2>&1; then \
		kubectl kustomize $(ROOT_DIR)/gitops/overlays/public >/dev/null; \
	fi
	@if command -v bats >/dev/null; then bats $(ROOT_DIR)/tests/bats; else echo "bats not installed; skipping"; fi

setup: ## Verify gcloud, terraform, and oc are installed
	bash $(SCRIPTS)/setup.sh

VENV_DOCS ?= .venv-docs
DOCS_MKDOCS := $(VENV_DOCS)/bin/mkdocs
DOCS_PIP := $(VENV_DOCS)/bin/pip

docs-venv: ## Create docs virtualenv
	@if ! command -v python3 >/dev/null 2>&1; then echo "python3 required" >&2; exit 1; fi
	@if [ ! -d "$(VENV_DOCS)" ]; then python3 -m venv "$(VENV_DOCS)"; fi
	@$(DOCS_PIP) install -q -r requirements-docs.txt

docs-preview: docs-venv ## Serve MkDocs locally
	@$(DOCS_MKDOCS) serve

docs-build: docs-venv ## Build MkDocs site (strict)
	@$(DOCS_MKDOCS) build --strict
