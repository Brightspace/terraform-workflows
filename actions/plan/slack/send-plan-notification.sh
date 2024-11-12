#!/usr/bin/env bash

set -euo pipefail

JOBS=$( curl --header "Authorization: token ${GITHUB_TOKEN}" \
	"${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}/jobs"
)
JOB_NAME_SUFFIX="Plan (${ENVIRONMENT})"
JOB_ID=$( echo "${JOBS}" | jq --raw-output ".jobs[] | select( .name | endswith(\"${JOB_NAME_SUFFIX}\") ) | .id" )
JOB_SUMMARY_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}#summary-${JOB_ID}"
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
COMMIT_NAME="${GITHUB_REPOSITORY}@${GITHUB_SHA:0:7}"

SLACK_USERNAME=$("${BASH_SOURCE%/*}/get-slack-username.sh")

TEXT=$(cat <<EOT
${SLACK_USERNAME} triggered Terraform deployment <${COMMIT_URL}|${COMMIT_NAME}> in ${ENVIRONMENT}.
Please review <${JOB_SUMMARY_URL}|the plan>.
EOT
)
SLACK_PAYLOAD=$( jq --null-input --arg text "${TEXT}" --arg channel "${SLACK_CHANNEL}" --compact-output \
	'{ channel: $channel, username: "Terraform notifier", icon_emoji: ":terraform:", text: $text }'
)
curl --request POST \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer ${SLACK_TOKEN}" \
	--data "${SLACK_PAYLOAD}" \
	"https://slack.com/api/chat.postMessage"
