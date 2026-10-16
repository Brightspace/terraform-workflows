#!/usr/bin/env bash

set -euo pipefail

export D2L_TF_CONFIGURE_TMP_DIR=$(mktemp -d)

errors=$(echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| if has("manage_aws_resources") and (.manage_aws_resources | type) != "boolean" then false
		  elif .manage_aws_resources == false then
		    ([.account_id, .provider_role_arn_ro, .provider_role_arn_rw, .provider_role_tfvar,
		      .workspaces[].provider_role_tfvar] | all(. == null))
		  else .account_id or (.provider_role_arn_ro and .provider_role_arn_rw)
		  end
		| select(. | not)
		| 1
		')
if [[ -n "${errors}" ]]; then
	echo '::error::Provide an AWS account or both provider roles, or set "manage_aws_resources": false without AWS account/role settings. "manage_aws_resources" must be a boolean.'
	exit 1
fi

role_suffix=${GITHUB_REPOSITORY/'/'/+}
role_suffix=${role_suffix/#'BrightspaceHypermediaComponents'/'BHC'}

echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| . as $account
		| (if .manage_aws_resources == false then null else
		    (.provider_role_arn_ro // "arn:aws:iam::\(.account_id):role/terraform/tfp+github+'"${role_suffix}"'") end) as $provider_role_arn_ro
		| (if .manage_aws_resources == false then null else
		    (.provider_role_arn_rw // "arn:aws:iam::\(.account_id):role/terraform/tfa+github+'"${role_suffix}"'") end) as $provider_role_arn_rw
		| $account.workspaces[]
		| (.provider_role_tfvar // $account.provider_role_tfvar // "terraform_role_arn") as $tfvar
		| {
			"manage_aws_resources": ($account.manage_aws_resources != false),
			"provider_role_arn_ro": $provider_role_arn_ro,
			"provider_role_arn_rw": $provider_role_arn_rw,
			"provider_role_tfvar": $tfvar,
			"environment": .environment,
			"key": (.key // .environment),
			"workspace_path": .path
		}' \
	 	- \
	| xargs -d'\n' -I{} env WSCONFIG='{}' "${HERE}/configure.sh"


echo "workspaces=$(cat ${D2L_TF_CONFIGURE_TMP_DIR}/workspaces)" >> "${GITHUB_OUTPUT}"
echo "config=$(cat ${D2L_TF_CONFIGURE_TMP_DIR}/config)" >> "${GITHUB_OUTPUT}"
