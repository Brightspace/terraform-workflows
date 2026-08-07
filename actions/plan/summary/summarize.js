const fs = require('node:fs');
const path = require('node:path');

/**
 * Return paths to leaf nodes in a nested object as arrays
 * Example input:
 * {
     "arn": "arn:aws:batch:us-east-1:730335506803:compute-environment/swtf-20260710191058686000000009",
	 "compute_resources": [{
	   "allocation_strategy": "BEST_FIT_PROGRESSIVE",
	 }],
	 "tags_all": {
  	   "STAGE": "swtf"
	 },
   }
 * Example output:
   [ ['arn'],
     ['compute_resources', 0, 'allocation_strategy']
	 ['tags_all', 'STAGE']
   ]
 */
function getNestedPaths(object) {
	const paths = [];
	for(const [keyStr, val] of Object.entries(object)) {
		if(typeof val === 'string') {
			// see if string is really a JSON object
			// this is needed for things like aws_batch_job_definition.container_properties
			try {
				const parsed = JSON.parse(val);
				const nestedPaths = getNestedPaths(parsed).filter(p => p.length > 0);
				paths.push(...nestedPaths.map(p => [keyStr, ...p]));
			} catch (e) {
				paths.push([keyStr]);
			}
		}
		else if(val === null || val === undefined || typeof val !== 'object') {
			paths.push([keyStr]);
		}
		else {
			const nestedPaths = getNestedPaths(val).filter(p => p.length > 0);
			if(nestedPaths.length === 0) { // empty object/array
				paths.push([keyStr]);
			}
			else {
				const key = Array.isArray(object) ? Number(keyStr) : keyStr;
				paths.push(...nestedPaths.map(p => [key, ...p]));
			}
		}
	}

	return paths;
}

function getValueAtPath(obj, nestedPath) {
	let current = obj;
	for (const key of nestedPath) {
		if (current === null || current === undefined) {
			return current;
		}
		current = current[key];
		if(typeof current === 'string') {
			// see if string is really a JSON object
			// this is needed for things like aws_batch_job_definition.container_properties
			try {
				const parsed = JSON.parse(current);
				current = parsed;
			} catch (e) {
			}
		}
	}
	return current;
}

function uniqueNestedPaths(paths) {
	const unique = new Map();
	for(const nestedPath of paths) {
		unique.set(nestedPath.map(p => `${p}`).join('.'), nestedPath)
	}
	return [...unique.values()];
}

function isUnknown(after_unknown, path) {
	for (let length = 0; length <= path.length; length += 1) {
		if (getValueAtPath(after_unknown, path.slice(0, length)) === true) {
			return true;
		}
	}
	return false;
}


function changedValues(change) {
	// see https://developer.hashicorp.com/terraform/internals/json-format#change-representation
	// Terraform output has before and after objects that store full state in nested objects,
	// as well as after_unknown object that has all unknown leaf values replaced with "true", and all known leaf values omitted.
	// Go through all these objects to get the paths to leaf nodes as arrays
	// then we can look up the values across before/after/after_unknown and compare them
	const changes = [];
	const afterUnknownPaths = getNestedPaths(change.after_unknown ?? {})
		  .filter(path => getValueAtPath(change.after_unknown, path) === true);
	const paths = uniqueNestedPaths([
		...getNestedPaths(change.before ?? {}),
		...getNestedPaths(change.after ?? {}),
		...afterUnknownPaths
	]);

	for (const path of paths) {
		const before = getValueAtPath(change.before, path);
		const after = getValueAtPath(change.after, path);
		const afterUnknown = isUnknown(change.after_unknown, path);
		// use stringify when comparing to handle empty objects/arrays
		if(JSON.stringify(before) !== JSON.stringify(after) || afterUnknown) {
			changes.push({
				key: path.map(p => `${p}`).join('.'),
				before,
				after: afterUnknown ? 'unknown' : after ?? null
			});
		}
	}
	return changes;
}

function isNoop(change) {
	return change.actions.length === 1 && (change.actions[0] === 'no-op' || change.actions[0] === 'read');
}

function getActionDescription(actions) {
	const actionsString = JSON.stringify(actions);
	if(actionsString === JSON.stringify(['update'])) {
		return 'UPDATED';
	}
	else if(actionsString === JSON.stringify(['create'])) {
		return 'CREATED';
	}
	else if(actionsString === JSON.stringify(['delete'])) {
		return 'DELETED';
	}
	else if(actionsString === JSON.stringify(['delete', 'create'])) {
		return 'RECREATED';
	}
	else if(actionsString === JSON.stringify(['create', 'delete'])) {
		return 'CREATED AND DELETED';
	}
	return actionsString;
}

function groupChangesByWorkspace(resources, workspaces) {
	const environments = {};
	for(const [key, changedResource] of Object.entries(resources)) {
		// changedResource is a set of key-value pairs where the key is the environment, and the value is the set of changes to the resource
		// if the resource is being changed in all environments, track the change details under the "all" object
		// otherwise, track the change details for each environment affected
		const environmentsAffected = Object.keys(changedResource);
		const actions = new Set(Object.values(changedResource).map(c => c.action));
		if(environmentsAffected.length === workspaces.length && actions.size === 1) {
			const action = [...actions.values()][0];
			if(!environments.all) {
				environments.all = [];
			}
			const changes = {};
			for(const environment of environmentsAffected) {
				// check if the before/after values are the same for all environments, or if some values are environment-specific
				for(const change of changedResource[environment].changes ?? []) {
					if(!changes[change.key]) {
						changes[change.key] = {
							before: change.before,
							after: change.after,
							affectedEnvCount: 1
						}
					}
					else {
						if(change.before !== changes[change.key].before) {
							changes[change.key].before = '(environment-specific)';
						}
						if(change.after !== changes[change.key].after) {
							changes[change.key].after = '(environment-specific)';
						}
						changes[change.key].affectedEnvCount++;
					}
				}
			}
			// check if any values were only changed in some environments
			for(const change of Object.values(changes)) {
				if(change.affectedEnvCount !== workspaces.length) {
					change.before = '(environment-specific)';
					change.after = '(environment-specific)';
				}
			}
			environments.all.push({
				resourceName: key,
				action,
				changes
			});
		}
		else {
			for(const environment of environmentsAffected) {
				if(!environments[environment]) {
					environments[environment] = [];
				}
				const changes = changedResource[environment].changes ?? [];
				environments[environment].push({
					resourceName: key,
					action: changedResource[environment].action,
					changes: Object.fromEntries(changes.map(c => ([c.key, c])))
				})
			}
		}
	}
	return environments;
}

function generateSummary(workspaces, plans) {
	const resources_modified = {};

	for(const workspace of workspaces) {
		const resources = plans[workspace]?.resource_changes ?? [];
		const changedResources = resources.filter(r => !isNoop(r.change));
		for(const resource of changedResources) {
			if(!resources_modified[resource.address]) {
				resources_modified[resource.address] = {};
			}
			const resourceChanges = {
				action: getActionDescription(resource.change.actions),
			};
			// if resource is being created/deleted, don't list all the individual changes
			if(resourceChanges.action === 'UPDATED' || resourceChanges.action === 'RECREATED') {
				resourceChanges.changes = changedValues(resource.change);
			}
			resources_modified[resource.address][workspace] = resourceChanges;
		}
	}

	const changes = groupChangesByWorkspace(resources_modified, workspaces);

	const lines = ['## Terraform plan summary'];
	for(const environment of Object.keys(changes)) {
		lines.push('<details>');
		const environmentName = environment === 'all' ? 'All environments' : environment;
		lines.push(`<summary>${environmentName}</summary>\n`);
		for(const resource of changes[environment]) {
			lines.push(`resource **${resource.resourceName}** will be **${resource.action}**`);
			lines.push('```');
			for(const [key, change] of Object.entries(resource.changes ?? {})) {
				lines.push(`${key}: ${change.before ?? '(not present)'} -> ${change.after}`);
			}
			lines.push('```');
		}
		lines.push('</details>');
	}
	return lines.join('\n');
}

module.exports = async ({ core, github, context }) => {
	const { ARTIFACTS_DIR, WORKSPACES } = process.env;
	const workspaceKeys = JSON.parse(WORKSPACES);

	const plans = {};
	for (const workspaceKey of workspaceKeys) {
		const planJsonPath = path.join(ARTIFACTS_DIR, workspaceKey, 'terraform.plan.json');
		plans[workspaceKey] = JSON.parse(fs.readFileSync(planJsonPath, 'utf8'));
	}

	let summary = generateSummary(workspaceKeys, plans);
	if (summary.length > 60000) {
		summary = `:rotating_light: Summary is truncated. See build log for full plan. :rotating_light:\n${summary.slice(0, 60000)}`;
	}

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
