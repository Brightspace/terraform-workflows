#!/usr/bin/env bash

set -euo pipefail

case "${MANAGE_AWS_RESOURCES:-true}" in
	true)
		if [ -z "${PROVIDER_ROLE_ARN:-}" ]; then
			echo '::error::An AWS provider role is required unless manage_aws_resources is false'
			exit 1
		fi
		;;
	false)
		if [ -n "${PROVIDER_ROLE_ARN:-}" ]; then
			echo '::error::Do not specify an AWS provider role when manage_aws_resources is false'
			exit 1
		fi
		;;
	*)
		echo '::error::manage_aws_resources must be true or false'
		exit 1
		;;
esac

trap onexit EXIT
onexit() {
	set +u

	rm "${BACKEND_CONFIG}"
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

echo "##[group]terraform init"
terraform init -input=false -backend-config="${BACKEND_CONFIG}" 2>&1
echo "##[endgroup]"

if [ "${MANAGE_AWS_RESOURCES:-true}" != "false" ]; then
	echo "TF_VAR_${PROVIDER_ROLE_TFVAR}=${PROVIDER_ROLE_ARN}" >> "${GITHUB_ENV}"
fi
