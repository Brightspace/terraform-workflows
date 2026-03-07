#!/usr/bin/env bash

set -euo pipefail

JOB_SUMMARY_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}#summary-${JOB_ID}"
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
COMMIT_NAME="${GITHUB_REPOSITORY}@${GITHUB_SHA:0:7}"

SLACK_USER=$("${BASH_SOURCE%/*}/get-slack-user.sh")

TEXT=$(cat <<EOT
${SLACK_USER} triggered Terraform deployment <${COMMIT_URL}|${COMMIT_NAME}> in workspace ${WORKSPACE_KEY}.
Please review <${JOB_SUMMARY_URL}|the plan>.
EOT
)
SLACK_PAYLOAD=$( jq --null-input --arg text "${TEXT}" --arg channel "${SLACK_CHANNEL}" --compact-output \
	'{ channel: $channel, username: "Terraform notifier", icon_emoji: ":terraform:", text: $text }'
)
curl --request POST \
	--header "Content-Type: application/json; charset=utf-8" \
	--header "Authorization: Bearer ${SLACK_TOKEN}" \
	--data "${SLACK_PAYLOAD}" \
	"https://slack.com/api/chat.postMessage"
