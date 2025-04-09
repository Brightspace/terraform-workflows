#!/usr/bin/env bash

set -euo pipefail

trap onexit EXIT
onexit() {
	set +u

	rm "${GITHUB_COMMENT_TEXT}" 2> /dev/null || true
}

if [ "${GITHUB_TOKEN}" == "" ]; then
	exit 0
fi

if [ "${COMMENTS_URL}" == "" ]; then
	exit 0
fi

if [ "${HAS_CHANGES}" == "false" ]; then
	exit 0
fi

TRUNCATED_WARNING=''
PLAN_TEXT=$(terraform show "${ARTIFACTS_DIR}/terraform.plan" -no-color | sed --silent '/Terraform will perform the following actions/,$p')
if [ "${PLAN_TEXT:0:60000}" != "${PLAN_TEXT}" ]; then
	NEWLINE=$'\n'
	PLAN_TEXT="${PLAN_TEXT:0:60000}"
 	TRUNCATED_WARNING=":rotating_light: Plan is truncated. See build log for full plan. :rotating_light:"
fi

GITHUB_COMMENT_TEXT=$(mktemp)
cat << EOF > "${GITHUB_COMMENT_TEXT}"
${TRUNCATED_WARNING}
<details>
<summary>
<b>${ENVIRONMENT} terraform plan</b> (${GITHUB_SHA})
has changes :yellow_circle:
</summary>

\`\`\`terraform
${PLAN_TEXT}
\`\`\`
</details>
EOF

GITHUB_COMMENT_BODY=$(jq \
	--null-input \
	-rR \
	--rawfile body "${GITHUB_COMMENT_TEXT}" \
	'{ body: $body }'
)

curl \
	--silent \
	--fail \
	--request POST \
	--url "${COMMENTS_URL}" \
	--header "Authorization: Bearer ${GITHUB_TOKEN}" \
	--data "@-" \
	<<< "${GITHUB_COMMENT_BODY}" \
	> /dev/null
