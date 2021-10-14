#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	# Step is allowed to fail
	exit 0
}

if [ "${GITHUB_TOKEN}" == "" ]; then
	exit 0
fi

if [ "${COMMENTS_URL}" == "" ]; then
	exit 0
fi

SEARCH_TERM="<b>${ENVIRONMENT} terraform plan</b>"
PREVIOUS_COMMENT_ID=$(curl \
	--silent \
	--fail \
	--request GET \
	--url "${COMMENTS_URL}?per_page=100" \
	--header "Authorization: Bearer ${GITHUB_TOKEN}" \
	| jq -r '[.[] | select(.body | contains("'"${SEARCH_TERM}"'"))] | last.node_id'
)

if [ "${PREVIOUS_COMMENT_ID}" != "" ]; then
	GRAPHQL_QUERY=$(cat << EOF
mutation {
  minimizeComment(input: {classifier: OUTDATED, subjectId: "${PREVIOUS_COMMENT_ID}"}) {
    minimizedComment {
      isMinimized
    }
  }
}
EOF
)

	GRAPHQL_CALL_BODY=$(jq \
		--null-input \
		-rR \
		--arg query "${GRAPHQL_QUERY}" \
		'{ query: $query }'
	)

	curl \
		--silent \
		--fail \
		--request POST \
		--url "https://api.github.com/graphql" \
		--header "Authorization: Bearer ${GITHUB_TOKEN}" \
		--data "@-" \
		<<< "${GRAPHQL_CALL_BODY}" \
		> /dev/null
fi
