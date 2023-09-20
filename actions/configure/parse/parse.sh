#!/usr/bin/env bash

set -euo pipefail

export D2L_TF_CONFIGURE_TMP_DIR=$(mktemp -d)

default_role_suffix=${GITHUB_REPOSITORY/'/'/+}
default_role_suffix=${default_role_suffix/#'BrightspaceHypermediaComponents'/'BHC'}

echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| . as $account
		| (.provider_role_arn_ro // "arn:aws:iam::\($account.account_id):role/terraform/tfp+github+'"${default_role_suffix}"'") as $provider_role_arn_ro
		| (.provider_role_arn_rw // "arn:aws:iam::\($account.account_id):role/terraform/tfa+github+'"${default_role_suffix}"'") as $provider_role_arn_rw
		| $account.workspaces[]
		| (.provider_role_tfvar // $account.provider_role_tfvar // "terraform_role_arn") as $tfvar
		| {
			"provider_role_arn_ro": $provider_role_arn_ro,
			"provider_role_arn_rw": $provider_role_arn_rw,
			"provider_role_tfvar": $tfvar,
			"environment": .environment,
			"workspace_path": .path
		}'

echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| . as $account
		| (.provider_role_arn_ro // "arn:aws:iam::\($account.account_id):role/terraform/tfp+github+'"${default_role_suffix}"'") as $provider_role_arn_ro
		| (.provider_role_arn_rw // "arn:aws:iam::\($account.account_id):role/terraform/tfa+github+'"${default_role_suffix}"'") as $provider_role_arn_rw
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
