#!/usr/bin/env bash

set -euo pipefail

if [ -f "${D2L_TF_CONFIGURE_TMP_DIR}/envs" ]; then
	D2L_TF_ENVS=$(cat "${D2L_TF_CONFIGURE_TMP_DIR}/envs")
	D2L_TF_CONFIG=$(cat "${D2L_TF_CONFIGURE_TMP_DIR}/config")
else
	D2L_TF_ENVS="[]"
	D2L_TF_CONFIG="{}"
fi

D2L_TF_ENVS=$(jq -cr \
	--argjson envconfig "${ENVCONFIG}" \
	'. += [$envconfig.environment]
	' \
	<<< "${D2L_TF_ENVS}"
)
D2L_TF_CONFIG=$(jq -cr \
	--argjson envconfig "${ENVCONFIG}" \
	'.[$envconfig.environment] = $envconfig' \
	<<< "${D2L_TF_CONFIG}"
)

echo "${D2L_TF_ENVS}" > "${D2L_TF_CONFIGURE_TMP_DIR}/envs"
echo "${D2L_TF_CONFIG}" > "${D2L_TF_CONFIGURE_TMP_DIR}/config"
