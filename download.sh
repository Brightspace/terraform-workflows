#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm "${DOWNLOAD_FILE}" 2> /dev/null || true
}

DOWNLOAD_FILE=$(mktemp --suffix .tar.gz)
EXTRACTION_DIR=$(mktemp -d)
echo "::set-output name=artifacts_dir::${EXTRACTION_DIR}"

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

aws s3 cp \
	"${S3_PATH}" \
	"${DOWNLOAD_FILE}" \
	> /dev/null

tar -xzf "${DOWNLOAD_FILE}" -C "${EXTRACTION_DIR}"
