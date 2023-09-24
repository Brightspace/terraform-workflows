#!/usr/bin/env bash

set -euo pipefail

if [ -f "${D2L_TF_CONFIGURE_TMP_DIR}/envs" ]; then
	D2L_TF_ENVS=$(cat "${D2L_TF_CONFIGURE_TMP_DIR}/envs")
	D2L_TF_CONFIG=$(cat "${D2L_TF_CONFIGURE_TMP_DIR}/config")
else
	D2L_TF_ENVS="[]"
	D2L_TF_CONFIG="{}"
fi

if [ "${GITHUB_EVENT_NAME}" = "pull_request" ]; then
	ROLE_ARN=$(jq -r '.provider_role_arn_ro' <<< "${ENVCONFIG}")
else
	ROLE_ARN=$(jq -r '.provider_role_arn_rw' <<< "${ENVCONFIG}")
fi

if [[ -z "${ROLE_ARN}" ]]; then
	ACCOUNT_ID=$(jq -r '.account_id' <<< "${ENVCONFIG}")
	if [[ -z "${ACCOUNT_ID}" ]]; then
		echo '::error::Either "account_id" or both of "provider_role_arn_ro" and "provider_role_arn_rw" must be provided'
		exit 1
	fi
	SUFFIX=${GITHUB_REPOSITORY/'/'/+}
	SUFFIX=${SUFFIX/#'BrightspaceHypermediaComponents'/'BHC'}
	if [ "${GITHUB_EVENT_NAME}" = "pull_request" ]; then
		ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/terraform/tfp+github+${SUFFIX}"
	else
		ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/terraform/tfa+github+${SUFFIX}"
	fi
fi

D2L_TF_ENVS=$(jq -cr \
	--argjson envconfig "${ENVCONFIG}" \
	'. += [$envconfig.environment]
	' \
	<<< "${D2L_TF_ENVS}"
)
D2L_TF_CONFIG=$(jq -cr \
	--argjson envconfig "${ENVCONFIG}" \
	--arg role_arn "${ROLE_ARN}" \
	'.[$envconfig.environment] = $envconfig
	| .[$envconfig.environment].provider_role_arn = $role_arn
	' \
	<<< "${D2L_TF_CONFIG}"
)

echo "${D2L_TF_ENVS}" > "${D2L_TF_CONFIGURE_TMP_DIR}/envs"
echo "${D2L_TF_CONFIG}" > "${D2L_TF_CONFIGURE_TMP_DIR}/config"
