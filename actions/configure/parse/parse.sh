#!/usr/bin/env bash

set -euo pipefail

export D2L_TF_CONFIGURE_TMP_DIR=$(mktemp -d)

echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| . as $account
		| $account.workspaces[]
		| .provider_role_tfvar // $account.provider_role_tfvar // "terraform_role_arn" as $tfvar
		| {
			"provider_role_arn_ro": $account.provider_role_arn_ro,
			"provider_role_arn_rw": $account.provider_role_arn_rw,
			"provider_role_tfvar": $tfvar,
			"environment": .environment,
			"workspace_path": .path,
			"variables": .variables
		}' \
	 	- \
	| xargs -d'\n' -I{} env ENVCONFIG='{}' "${HERE}/../configure.sh"


echo "::set-output name=environments::$(cat ${D2L_TF_CONFIGURE_TMP_DIR}/envs)"
echo "::set-output name=config::$(cat ${D2L_TF_CONFIGURE_TMP_DIR}/config)"
