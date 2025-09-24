#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm "${BACKEND_CONFIG}"
	rm "${GITHUB_STEP_SUMMARY_PLAN_OUTPUT}" 2> /dev/null || true
}

REFRESH=""
if [ "${GITHUB_EVENT_NAME}" == "pull_request" ]; then
	ROLE_KIND="r"

	if [ "${REFRESH_ON_PR}" == "false" ]; then
		REFRESH="-refresh=false"
	fi
else
	ROLE_KIND="m"
fi

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
	  role_arn = "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+${ROLE_KIND}"
	}
	EOF
else
	cat >> "${BACKEND_CONFIG}" <<- EOF
	role_arn       = "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+${ROLE_KIND}"
	EOF
fi

echo "##[group]terraform init"
terraform init -input=false -backend-config="${BACKEND_CONFIG}"
echo "##[endgroup]"

if [ "${REQUIRE_LOCKFILE}" == "true" ]; then
	git add --intent-to-add .terraform.lock.hcl
	LOCKFILE_DIFF=$(git diff -- .terraform.lock.hcl)
	if echo "${LOCKFILE_DIFF}" | grep --quiet --extended-regexp '^[+-]\s*provider\s+"'; then
		echo '::error ::Changes detected in provider declarations in .terraform.lock.hcl. Please review and commit the lock file changes.'
		echo "${LOCKFILE_DIFF}"
		exit 1
	fi
fi

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
		echo "has_changes=false" >> "${GITHUB_OUTPUT}"
		echo "plan_json={}" >> "${GITHUB_OUTPUT}"
		exit 0
		;;

	"2")
		# success with changes
		echo "has_changes=true" >> "${GITHUB_OUTPUT}"
		;;

	*)
		# fail
		echo "terraform plan failed ${PLAN_EXIT_CODE}"
		exit ${PLAN_EXIT_CODE}
		;;
esac
set -e

# output planned changes to step summary
GITHUB_STEP_SUMMARY_PLAN_OUTPUT=$(mktemp)
terraform show "${ARTIFACTS_DIR}/terraform.plan" -no-color \
	| sed --silent '/Terraform will perform the following actions/,$p' \
	> "${GITHUB_STEP_SUMMARY_PLAN_OUTPUT}"

let SUMMARY_PLAN_TEXT_TRUNCATE_BYTES=1048576-20
echo '```terraform' > ${GITHUB_STEP_SUMMARY}
head --bytes=${SUMMARY_PLAN_TEXT_TRUNCATE_BYTES} "${GITHUB_STEP_SUMMARY_PLAN_OUTPUT}" >> ${GITHUB_STEP_SUMMARY}
echo '```' >> ${GITHUB_STEP_SUMMARY}

# print planned changes to console
terraform show "${ARTIFACTS_DIR}/terraform.plan" | sed --silent '/Terraform will perform the following actions/,$p'
# output of the command above ends with a colour code without trailing newline, which can mess up following workflow commands
echo

if [ "${GITHUB_EVENT_NAME}" != "pull_request" ]; then
	echo "Approve the deployment here: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

if [[ -d .artifacts ]]; then
	echo "Collecting $PWD/.artifacts:"
	cp -rv .artifacts "${ARTIFACTS_DIR}"
else
	echo "No $PWD/.artifacts directory found"
fi

terraform show -json "${ARTIFACTS_DIR}/terraform.plan" > "${ARTIFACTS_DIR}/terraform.plan.json"
echo "plan_path=${ARTIFACTS_DIR}/terraform.plan" >> "${GITHUB_OUTPUT}"
echo "plan_json_path=${ARTIFACTS_DIR}/terraform.plan.json" >> "${GITHUB_OUTPUT}"
