#!/usr/bin/env bash

set -euo pipefail

if [ -f "${D2L_TF_CONFIGURE_TMP_DIR}/workspaces" ]; then
	D2L_TF_WORKSPACES=$(cat "${D2L_TF_CONFIGURE_TMP_DIR}/workspaces")
	D2L_TF_CONFIG=$(cat "${D2L_TF_CONFIGURE_TMP_DIR}/config")
else
	D2L_TF_WORKSPACES="[]"
	D2L_TF_CONFIG="{}"
fi

if [ "${GITHUB_EVENT_NAME}" = "pull_request" ]; then
	ROLE_ARN=$(jq -r '.provider_role_arn_ro' <<< "${WSCONFIG}")
else
	ROLE_ARN=$(jq -r '.provider_role_arn_rw' <<< "${WSCONFIG}")
fi

if [[ -z "${ROLE_ARN}" ]]; then
	ACCOUNT_ID=$(jq -r '.account_id' <<< "${WSCONFIG}")
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

D2L_TF_WORKSPACES=$(jq -cr \
	--argjson wsconfig "${WSCONFIG}" \
	'. += [$wsconfig.key]
	' \
	<<< "${D2L_TF_WORKSPACES}"
)
D2L_TF_CONFIG=$(jq -cr \
	--argjson wsconfig "${WSCONFIG}" \
	--arg role_arn "${ROLE_ARN}" \
	'.[$wsconfig.key] = $wsconfig
	| .[$wsconfig.key].provider_role_arn = $role_arn
	' \
	<<< "${D2L_TF_CONFIG}"
)

echo "${D2L_TF_WORKSPACES}" > "${D2L_TF_CONFIGURE_TMP_DIR}/workspaces"
echo "${D2L_TF_CONFIG}" > "${D2L_TF_CONFIGURE_TMP_DIR}/config"
