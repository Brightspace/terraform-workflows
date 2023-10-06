#!/usr/bin/env bash

set -euo pipefail

export D2L_TF_CONFIGURE_TMP_DIR=$(mktemp -d)

errors=$(echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| .account_id or (.provider_role_arn_ro and .provider_role_arn_rw)
		| select(. | not)
		| 1
		')
if [[ -n "${errors}" ]]; then
	echo '::error::Either "account_id" or both of "provider_role_arn_ro" and "provider_role_arn_rw" must be provided'
	exit 1
fi

role_suffix=${GITHUB_REPOSITORY/'/'/+}
role_suffix=${role_suffix/#'BrightspaceHypermediaComponents'/'BHC'}

echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| . as $account
		| (.provider_role_arn_ro // "arn:aws:iam::\(.account_id):role/terraform/tfp+github+'"${role_suffix}"'") as $provider_role_arn_ro
		| (.provider_role_arn_rw // "arn:aws:iam::\(.account_id):role/terraform/tfa+github+'"${role_suffix}"'") as $provider_role_arn_rw
		| $account.workspaces[]
		| (.provider_role_tfvar // $account.provider_role_tfvar // "terraform_role_arn") as $tfvar
		| {
			"provider_role_arn_ro": $provider_role_arn_ro,
			"provider_role_arn_rw": $provider_role_arn_rw,
			"provider_role_tfvar": $tfvar,
			"environment": .environment,
			"workspace_path": .path
		}' \
	 	- \
	| xargs -d'\n' -I{} env ENVCONFIG='{}' "${HERE}/../configure.sh"


echo "environments=$(cat ${D2L_TF_CONFIGURE_TMP_DIR}/envs)" >> "${GITHUB_OUTPUT}"
echo "config=$(cat ${D2L_TF_CONFIGURE_TMP_DIR}/config)" >> "${GITHUB_OUTPUT}"
