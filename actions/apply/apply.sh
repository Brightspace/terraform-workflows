#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm "${BACKEND_CONFIG}" 2> /dev/null || true
}

BACKEND_CONFIG=$(mktemp)
cat > "${BACKEND_CONFIG}" << EOF
region         = "us-east-1"
bucket         = "d2l-terraform-state"
dynamodb_table = "d2l-terraform-state"
key            = "github/${GITHUB_REPOSITORY}/${ENVIRONMENT}.tfstate"
EOF

MAJOR_VERSION=$(terraform version | grep -oP 'Terraform v\K\d+')
MINOR_VERSION=$(terraform version | grep -oP 'Terraform v\d+\.\K\d+')
if (( "${MAJOR_VERSION}" * 1000 + "${MINOR_VERSION}" >= 1006 )); then
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
terraform init -input=false -backend-config="${BACKEND_CONFIG}"
echo "##[endgroup]"

terraform show "${PLAN_PATH}"
terraform apply -input=false "${PLAN_PATH}"
