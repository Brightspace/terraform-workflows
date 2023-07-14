#!/usr/bin/env bash

set -euo pipefail

. "${BASH_SOURCE%/*}/skip_prs.sh"

trap onexit EXIT
onexit() {
	set +u

	rm "${TAR_FILE}" 2> /dev/null || true
}

TAR_FILE=$(mktemp --suffix=.tar.gz)

shopt -s globstar
tar -czf "${TAR_FILE}" -C "${PATH_TO_ARCHIVE}" .
shopt -u globstar

ASSUMEROLE_RESULT=$(aws \
	sts assume-role \
	--role-arn "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+m" \
	--role-session-name "githubaction-sha-${GITHUB_SHA}" \
)

AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<< "${ASSUMEROLE_RESULT}")
AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<< "${ASSUMEROLE_RESULT}")
AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<< "${ASSUMEROLE_RESULT}")

ENVIRONMENT_SAFE=$(xxd -p <<< "${ENVIRONMENT}")
S3_PATH="s3://d2l-terraform-plans/github/${GITHUB_REPOSITORY}/${GITHUB_SHA}/${GITHUB_WORKFLOW}/${GITHUB_RUN_ID}/${ENVIRONMENT_SAFE}.tar.gz"

echo "##[group]upload plan"
aws s3 cp \
	"${TAR_FILE}" \
	"${S3_PATH}"
echo "##[endgroup]"
