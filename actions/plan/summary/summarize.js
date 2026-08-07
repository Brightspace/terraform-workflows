module.exports = async ({ core, github, context }) => {
	if (!context.payload.pull_request) {
		return;
	}

	await github.rest.issues.createComment({
		owner: context.repo.owner,
		repo: context.repo.repo,
		issue_number: context.payload.pull_request.number,
		body: 'TODO'
	});
}
