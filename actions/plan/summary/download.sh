#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm -r "${DOWNLOAD_DIR}" 2> /dev/null || true
}

DOWNLOAD_DIR=$(mktemp -d)
EXTRACTION_DIR=$(mktemp -d)
echo "artifacts_dir=${EXTRACTION_DIR}" >> "${GITHUB_OUTPUT}"

ASSUMEROLE_RESULT=$(aws \
	sts assume-role \
	--role-arn "arn:aws:iam::891724658749:role/github/${GITHUB_REPOSITORY%/*}+${GITHUB_REPOSITORY#*/}+r" \
	--role-session-name "githubaction-sha-${GITHUB_SHA}" \
)

AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<< "${ASSUMEROLE_RESULT}")
AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<< "${ASSUMEROLE_RESULT}")
AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<< "${ASSUMEROLE_RESULT}")

# parse WORKSPACES JSON array into bash array
readarray -t WORKSPACE_LIST < <(jq -r '.[]' <<< "${WORKSPACES}")

for WORKSPACE_KEY in "${WORKSPACE_LIST[@]}"; do
	# workspace key is hex-encoded to form the archive name, see plan/archive.sh
	WORKSPACE_KEY_SAFE=$(xxd -p <<< "${WORKSPACE_KEY}")
	DOWNLOAD_FILE="${DOWNLOAD_DIR}/${WORKSPACE_KEY_SAFE}.tar.gz"

	aws s3 cp \
		"s3://d2l-terraform-plans/github-prs/${GITHUB_REPOSITORY}/${GITHUB_SHA}/${GITHUB_WORKFLOW}/${GITHUB_RUN_ID}/${WORKSPACE_KEY_SAFE}.tar.gz" \
		"${DOWNLOAD_FILE}" \
		> /dev/null

	TARGET="${EXTRACTION_DIR}/${WORKSPACE_KEY}"
	mkdir -p "${TARGET}"
	tar -xzf "${DOWNLOAD_FILE}" -C "${TARGET}"
done
