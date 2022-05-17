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
role_arn       = "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+tfstate-manager"
bucket         = "d2l-terraform-state"
dynamodb_table = "d2l-terraform-state"
key            = "github/${GITHUB_REPOSITORY}/${ENVIRONMENT}.tfstate"
EOF

echo "##[group]terraform init"
terraform init -input=false -backend-config="${BACKEND_CONFIG}"
echo "##[endgroup]"

echo "##[group]restore-artifacts"
if [[ -d "${PLAN_ARTIFACTS}/.artifacts" ]]; then
	echo "Copying additional artifacts to $PWD/.artifacts:"
	cp -rv "${PLAN_ARTIFACTS}/.artifacts" .
else
	echo "Plan did not contain additional artifacts"
fi
echo "##[endgroup]"

terraform show "${PLAN_PATH}"
terraform apply -input=false "${PLAN_PATH}"
