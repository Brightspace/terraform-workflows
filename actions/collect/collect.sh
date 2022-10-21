#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm -r "${DETAILS_DIR}" 2> /dev/null || true
}

ANY_CHANGES="false"
RESULTS=$(jq -cr '. | .all=[] | .changed=[] | .details={}' <<< {})

shopt -s nullglob
for f in "${DETAILS_DIR}"/*; do

	ENVIRONMENT=$(jq -r '.environment' "${f}")
	HAS_CHANGES=$(jq -r '.has_changes' "${f}")

	RESULTS=$(jq -cr \
		--arg environment "${ENVIRONMENT}" \
		--argjson details "$(<"${f}")" \
		'.
		| .all += [$environment]
		| .details[$environment] = $details
		' \
		<<< "${RESULTS}"
	)

	if [ "${HAS_CHANGES}" != "true" ]; then
		continue
	fi

	ANY_CHANGES="true"

	RESULTS=$(jq -cr \
		--arg environment "${ENVIRONMENT}" \
		'. | .changed += [$environment]' \
		<<< "${RESULTS}"
	)
done
shopt -u nullglob

echo "has_changes=${ANY_CHANGES}" >> "$GITHUB_OUTPUT"
echo "all=$(jq -cr '.all' <<< "${RESULTS}")" >> "$GITHUB_OUTPUT"
echo "changed=$(jq -cr '.changed' <<< "${RESULTS}")" >> "$GITHUB_OUTPUT"
echo "config=$(jq -cr '.details' <<< "${RESULTS}")" >> "$GITHUB_OUTPUT"

echo "Results:"
jq <<< "${RESULTS}"
