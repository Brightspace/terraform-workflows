#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm "${BACKEND_CONFIG}"
}

REFRESH=""
if [ "${GITHUB_EVENT_NAME}" == "pull_request" ]; then
	ROLE_KIND="reader"

	if [ "${REFRESH_ON_PR}" == "false" ]; then
		REFRESH="-refresh=false"
	fi
else
	ROLE_KIND="manager"
fi

BACKEND_CONFIG=$(mktemp)
cat > "${BACKEND_CONFIG}" << EOF
region         = "us-east-1"
role_arn       = "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+tfstate-${ROLE_KIND}"
bucket         = "d2l-terraform-state"
dynamodb_table = "d2l-terraform-state"
key            = "github/${GITHUB_REPOSITORY}/${ENVIRONMENT}.tfstate"
EOF

echo "##[group]terraform init"
terraform init -input=false -backend-config="${BACKEND_CONFIG}"
echo "##[endgroup]"

set +e
echo "##[group]terraform plan"
terraform plan \
	-input=false \
	-lock=false \
	-detailed-exitcode \
	-var "${PROVIDER_ROLE_TFVAR}=${PROVIDER_ROLE_ARN}" \
	-out "${ARTIFACTS_DIR}/terraform.plan" \
	${REFRESH}
PLAN_EXIT_CODE=$?
echo "##[endgroup]"

case "${PLAN_EXIT_CODE}" in

	"0")
		# success with no changes
		echo "::set-output name=has_changes::false"
		echo "::set-output name=plan_json::{}"
		exit 0
		;;

	"2")
		# success with changes
		echo "::set-output name=has_changes::true"
		;;

	*)
		# fail
		echo "terraform plan failed ${PLAN_EXIT_CODE}"
		exit ${PLAN_EXIT_CODE}
		;;
esac
set -e

# print only planned changes without noisy drift detection
# https://github.com/hashicorp/terraform/issues/28803
terraform show "${ARTIFACTS_DIR}/terraform.plan" | sed --silent '/Terraform will perform the following actions/,$p'
# output of the command above ends with a colour code without trailing newline, which can mess up following workflow commands
echo

if [[ -d .artifacts ]]; then
	cp -r .artifacts "${ARTIFACTS_DIR}"
fi

PLAN_JSON=$(terraform show -json "${ARTIFACTS_DIR}/terraform.plan" | tee "${ARTIFACTS_DIR}/terraform.plan.json")
echo "::set-output name=plan_json::${PLAN_JSON}"
