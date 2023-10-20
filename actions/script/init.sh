#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm "${BACKEND_CONFIG}"
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

echo "##[group]terraform init"
terraform init -input=false -backend-config="${BACKEND_CONFIG}"
echo "##[endgroup]"

echo "TF_VAR_${PROVIDER_ROLE_TFVAR}=${PROVIDER_ROLE_ARN}" >> "${GITHUB_ENV}"
