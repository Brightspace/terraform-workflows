#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm -r "${DOWNLOAD_DIR}" 2> /dev/null || true
	rm -r "${EXTRACTION_DIR}" 2> /dev/null || true
}

DOWNLOAD_DIR=$(mktemp -d)

ASSUMEROLE_RESULT=$(aws \
	sts assume-role \
	--role-arn "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+r" \
	--role-session-name "githubaction-sha-${GITHUB_SHA}" \
)

AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<< "${ASSUMEROLE_RESULT}")
AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<< "${ASSUMEROLE_RESULT}")
AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<< "${ASSUMEROLE_RESULT}")

S3_PATH="s3://d2l-terraform-plans/github/${GITHUB_REPOSITORY}/${GITHUB_SHA}/${GITHUB_WORKFLOW}/${GITHUB_RUN_ID}/"

aws s3 sync \
	"${S3_PATH}" \
	"${DOWNLOAD_DIR}" \
	> /dev/null

shopt -s nullglob
for f in "${DOWNLOAD_DIR}"/*.tar.gz; do
	EXTRACTION_DIR=$(mktemp -d)

	tar -xzf "${f}" -C "${EXTRACTION_DIR}"

	ENVIRONMENT_SAFE=$(jq -r '.environment' "${EXTRACTION_DIR}/details.json" | xxd -p)
	mv "${EXTRACTION_DIR}/details.json" "${DETAILS_DIR}/${ENVIRONMENT_SAFE}.json"

	rm -r "${EXTRACTION_DIR}"
done
