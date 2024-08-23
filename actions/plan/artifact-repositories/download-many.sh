#!/usr/bin/env bash

set -euo pipefail

export D2L_ARTIFACT_REPOSITORIES_TMP_DIR=$(mktemp -d)
trap onexit EXIT
onexit() {
	set +u

	rm -r "${D2L_ARTIFACT_REPOSITORIES_TMP_DIR}" 2> /dev/null || true
}

errors=$(echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '
		.[]
		| .slug and .ref and .secret_num
		| select(. | not)
		| 1
		')
if [[ -n "${errors}" ]]; then
	echo '::error::Each artifact_repositories entry requires slug, ref and secret_num properties'
	exit 1
fi

echo "${CONFIG}" \
	| yq -o=json . - \
	| jq -cr '.[] | [.slug, .ref, .secret_num] | .[]' - \
	| xargs -n3 "${HERE}/download-one.sh"
