#!/usr/bin/env bash

set -euo pipefail

check_slug() {
	local slug="${1}"; shift

	if [[ ! "${slug}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+$ ]]; then
		2>&1 echo "Invalid repository slug: ${slug}"
		exit 1
	fi
}

check_ref() {
	local ref="${1}"; shift

	if [[ ! "${ref}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		2>&1 echo "Invalid repository ref: ${ref}"
		exit 1
	fi
}

main() {
	local slug="${1}"; shift
	local ref="${1}"; shift
	local secret_num="${1}"; shift

	check_slug "${slug}"
	check_ref "${ref}"

	local download_file_path="${D2L_ARTIFACT_REPOSITORIES_TMP_DIR}/${slug//[\/]/_}_${ref}.tar"

	local token_variable_name="ARTIFACT_REPOSITORIES_SECRET_${secret_num}"
	wget \
		--header "Authorization: Bearer ${!token_variable_name}" \
		--output-document "${download_file_path}" \
		"https://api.github.com/repos/${slug}/tarball/${ref}"

	local target="${ARTIFACTS_DIR}/artifact_repositories/${slug}/${ref}"
	mkdir -p "${target}"

	tar xvf "${download_file_path}" --strip-components=1 -C "${target}"
}

main "${@}"
