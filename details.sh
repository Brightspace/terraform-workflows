#!/usr/bin/env bash

set -euo pipefail

. "${BASH_SOURCE%/*}/skip_prs.sh"

TERRAFORM_VERSION_JSON=$(terraform version -json)
if [ "${TERRAFORM_VERSION_JSON:0:1}" == "{" ]; then
	TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
else
	TERRAFORM_VERSION="${TERRAFORM_VERSION_INPUT}"
fi

jq \
	--arg run_id "${GITHUB_RUN_ID}" \
	--arg environment "${ENVIRONMENT}" \
	--arg workspace_path "${WORKSPACE_PATH}" \
	--arg has_changes "${HAS_CHANGES}" \
	--arg terraform_version "${TERRAFORM_VERSION}" \
	'.
	| .run_id=$run_id
  	| .environment=$environment
	| .workspace_path=$workspace_path
	| .has_changes=$has_changes
	| .terraform_version=$terraform_version
	' \
  <<< {} > "${ARTIFACTS_DIR}/details.json"
