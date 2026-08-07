const fs = require('node:fs');
const path = require('node:path');

module.exports = async ({ core, github, context }) => {
	const { ARTIFACTS_DIR, WORKSPACES } = process.env;
	const workspaceKeys = JSON.parse(WORKSPACES);

	const rows = workspaceKeys.map((workspaceKey) => {
		const planJsonPath = path.join(ARTIFACTS_DIR, workspaceKey, 'terraform.plan.json');
		try {
			JSON.parse(fs.readFileSync(planJsonPath, 'utf8'));
			return `Parsed plan for ${workspaceKey}`;
		} catch (e) {
			return `Error getting plan for ${workspaceKey}`;
		}
	})

	const summary = rows.join('\n');

	if (!context.payload.pull_request) {
		return;
	}

	await github.rest.issues.createComment({
		owner: context.repo.owner,
		repo: context.repo.repo,
		issue_number: context.payload.pull_request.number,
		body: summary
	});
}
