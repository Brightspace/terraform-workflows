#!/usr/bin/env bash

set -euo pipefail

terraform_with_deferred_stderr() {
	local terraform_stderr
	local terraform_exit_code

	terraform_stderr=$(mktemp)
	if terraform "$@" 2> "${terraform_stderr}"; then
		terraform_exit_code=0
	else
		terraform_exit_code=$?
	fi

	cat "${terraform_stderr}"
	rm "${terraform_stderr}"
	return "${terraform_exit_code}"
}

trap onexit EXIT
onexit() {
	set +u

	rm "${BACKEND_CONFIG}" 2> /dev/null || true
}

BACKEND_CONFIG=$(mktemp)
cat > "${BACKEND_CONFIG}" << EOF
region         = "us-east-1"
bucket         = "d2l-terraform-state"
key            = "github/${GITHUB_REPOSITORY}/${WORKSPACE_KEY}.tfstate"
EOF

MAJOR_VERSION=$(terraform version | grep -oP 'Terraform v\K\d+')
MINOR_VERSION=$(terraform version | grep -oP 'Terraform v\d+\.\K\d+')
TF_VERSION_NUM=$(( "${MAJOR_VERSION}" * 1000 + "${MINOR_VERSION}" ))

if (( TF_VERSION_NUM >= 1010 )); then
	cat >> "${BACKEND_CONFIG}" <<- EOF
	use_lockfile   = true
	EOF
else
	cat >> "${BACKEND_CONFIG}" <<- EOF
	dynamodb_table = "d2l-terraform-state"
	EOF
fi

if (( TF_VERSION_NUM >= 1006 )); then
	cat >> "${BACKEND_CONFIG}" <<- EOF
	assume_role = {
	  role_arn = "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+m"
	}
	EOF
else
	cat >> "${BACKEND_CONFIG}" <<- EOF
	role_arn       = "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+m"
	EOF
fi

echo "##[group]restore-artifacts"
if [[ -d "${PLAN_ARTIFACTS}/.artifacts" ]]; then
	echo "Copying additional artifacts to $PWD/.artifacts:"
	cp -rv "${PLAN_ARTIFACTS}/.artifacts" .
else
	echo "Plan did not contain additional artifacts"
fi
echo "##[endgroup]"

echo "##[group]terraform init"
terraform_with_deferred_stderr init -input=false -backend-config="${BACKEND_CONFIG}"
echo "##[endgroup]"

PARALLELISM_FLAG=""
# An unset optional `type: number` workflow_call input defaults to 0, not empty:
# https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_callinputs
# -parallelism=0 would stall terraform entirely, so treat 0 the same as unset.
if [ -n "${PARALLELISM:-}" ] && [ "${PARALLELISM}" != "0" ]; then
	PARALLELISM_FLAG="-parallelism=${PARALLELISM}"
fi

terraform_with_deferred_stderr show "${PLAN_PATH}"
terraform_with_deferred_stderr apply -input=false ${PARALLELISM_FLAG} "${PLAN_PATH}"
