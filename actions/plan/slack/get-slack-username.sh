#!/usr/bin/env bash

set -euo pipefail

ASSUMEROLE_RESULT=$(aws \
	sts assume-role \
	--role-arn 'arn:aws:iam::022062736489:role/employee_table_reader_role20201120203944096600000001' \
	--role-session-name "githubaction-sha-${GITHUB_SHA}" \
)

AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<< "${ASSUMEROLE_RESULT}")
AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<< "${ASSUMEROLE_RESULT}")
AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<< "${ASSUMEROLE_RESULT}")

D2L_EMAIL=$(aws dynamodb query \
	--region ca-central-1 \
	--table-name D2LEmployees \
	--index-name GitHubUserIdIndex \
	--key-condition-expression "GitHubUserId = :u" \
	--expression-attribute-values "{\":u\": {\"N\": \"${GITHUB_ACTOR_ID}\"}}" \
	--query 'Items[].D2LEmail.S' \
	--output text)

if [ -n "${D2L_EMAIL}" ]; then
	# mention the user in Slack if we can find them
	echo "<@${D2L_EMAIL%%@*}>"
else
	# fall back to using the GitHub username directly
	echo "${GITHUB_ACTOR}"
fi
