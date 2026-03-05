#!/usr/bin/env bash

set -euo pipefail

JOBS=$( curl --header "Authorization: token ${GITHUB_TOKEN}" \
	"${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}/jobs"
)
JOB_NAME_SUFFIX="Apply (${WORKSPACE_KEY})"
JOB_URL=$( echo "${JOBS}" | jq --raw-output ".jobs[] | select( .name | endswith(\"${JOB_NAME_SUFFIX}\") ) | .html_url" )
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
COMMIT_NAME="${GITHUB_REPOSITORY}@${GITHUB_SHA:0:7}"

if [ "${JOB_STATUS}" == 'success' ]; then
	TEXT="Terraform apply <${JOB_URL}|succeeded> for <${COMMIT_URL}|${COMMIT_NAME}> in workspace ${WORKSPACE_KEY}."
else
	TEXT="Terraform apply <${JOB_URL}|failed> for <${COMMIT_URL}|${COMMIT_NAME}> in workspace ${WORKSPACE_KEY}! :alert:"
fi
SLACK_PAYLOAD="{
	\"channel\": \"${SLACK_CHANNEL}\",
	\"username\": \"Terraform notifier\",
	\"icon_emoji\": \":terraform:\",
	\"text\": \"${TEXT}\",
}"
curl --request POST \
	--header "Content-Type: application/json; charset=utf-8" \
	--header "Authorization: Bearer ${SLACK_TOKEN}" \
	--data "${SLACK_PAYLOAD}" \
	"https://slack.com/api/chat.postMessage"
