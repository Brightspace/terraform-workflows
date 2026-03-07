#!/usr/bin/env bash

set -euo pipefail

JOB_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/job/${JOB_ID}"
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
