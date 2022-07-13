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
	| .[$envconfig.environment].variables = {}
	' \
	<<< "${D2L_TF_CONFIG}"
)

echo "${D2L_TF_ENVS}" > "${D2L_TF_CONFIGURE_TMP_DIR}/envs"
echo "${D2L_TF_CONFIG}" > "${D2L_TF_CONFIGURE_TMP_DIR}/config"
