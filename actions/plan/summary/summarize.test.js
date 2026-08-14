const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const {
	getNestedPaths,
	getValueAtPath,
	isMarked,
	changedValues,
	isNoop,
	getActionDescription,
	groupChangesByWorkspace,
	generateSummary
} = require('./summarize.js');

describe('getNestedPaths', () => {
	it('returns one path per key for a flat object', () => {
		const paths = getNestedPaths({ arn: 'abc', count: 3 });
		assert.deepEqual(paths, [['arn'], ['count']]);
	});

	it('walks nested objects and arrays, converting array indices to numbers', () => {
		const paths = getNestedPaths({
			compute_resources: [{ allocation_strategy: 'BEST_FIT_PROGRESSIVE' }],
			tags_all: { STAGE: 'swtf' }
		});
		assert.deepEqual(paths, [
			['compute_resources', 0, 'allocation_strategy'],
			['tags_all', 'STAGE']
		]);
	});

	it('parses JSON-encoded string values and recurses into them', () => {
		const paths = getNestedPaths({
			container_properties: JSON.stringify({ image: 'arn' })
		});
		assert.deepEqual(paths, [['container_properties', 'image']]);
	});

	it('treats a string that is not valid JSON as a plain leaf', () => {
		const paths = getNestedPaths({ name: 'not-json' });
		assert.deepEqual(paths, [['name']]);
	});

	it('treats empty objects/arrays as leaves rather than recursing further', () => {
		const paths = getNestedPaths({ layers: [], tags: {} });
		assert.deepEqual(paths, [['layers'], ['tags']]);
	});

	it('treats null and undefined values as leaves', () => {
		const paths = getNestedPaths({ a: null, b: undefined });
		assert.deepEqual(paths, [['a'], ['b']]);
	});
});

describe('getValueAtPath', () => {
	const obj = {
		tags_all: { STAGE: 'swtf' },
		container_properties: JSON.stringify({ image: 'arn' })
	};

	it('resolves a simple nested path', () => {
		assert.equal(getValueAtPath(obj, ['tags_all', 'STAGE']), 'swtf');
	});

	it('transparently parses JSON-encoded strings while traversing', () => {
		assert.equal(getValueAtPath(obj, ['container_properties', 'image']), 'arn');
	});

	it('returns null/undefined without throwing when an intermediate value is missing', () => {
		assert.equal(getValueAtPath(obj, ['missing', 'child']), undefined);
		assert.equal(getValueAtPath({ a: null }, ['a', 'child']), null);
	});
});

describe('isMarked', () => {
	const marked = {
		architectures: [false],
		last_modified: true,
		layers: [],
		tags: {}
	};

	it('returns true when the exact leaf is true', () => {
		assert.equal(isMarked(marked, ['last_modified']), true);
	});

	it('returns true when an ancestor along the path is true', () => {
		assert.equal(isMarked({ whole: true }, ['whole', 'child']), true);
	});

	it('returns false when nothing along the path is true', () => {
		assert.equal(isMarked(marked, ['architectures', 0]), false);
		assert.equal(isMarked(marked, ['layers']), false);
		assert.equal(isMarked(marked, ['tags']), false);
	});
});

describe('changedValues', () => {
	it('includes only keys whose value changed between before/after', () => {
		const changes = changedValues({
			before: { name: 'a', unchanged: 'x' },
			after: { name: 'b', unchanged: 'x' }
		});
		assert.deepEqual(changes, [{ key: 'name', before: 'a', after: 'b', isSensitive: false }]);
	});

	it('reports created values with before as null', () => {
		const changes = changedValues({ before: {}, after: { name: 'new' } });
		assert.deepEqual(changes, [{ key: 'name', before: undefined, after: 'new', isSensitive: false }]);
	});

	it('reports deleted values with after as null', () => {
		const changes = changedValues({ before: { name: 'old' }, after: {} });
		assert.deepEqual(changes, [{ key: 'name', before: 'old', after: null, isSensitive: false }]);
	});

	it('marks unknown after-apply values', () => {
		const changes = changedValues({
			before: { name: 'old' },
			after: { name: 'old' },
			after_unknown: { name: true }
		});
		assert.deepEqual(changes, [{ key: 'name', before: 'old', after: 'unknown', isSensitive: false }]);
	});

	it('flags sensitive changes', () => {
		const changes = changedValues({
			before: { password: 'old' },
			after: { password: 'new' },
			after_sensitive: { password: true }
		});
		assert.deepEqual(changes, [{ key: 'password', before: 'old', after: 'new', isSensitive: true }]);
	});

	it('joins keys for nested paths', () => {
		const changes = changedValues({
			before: { tags_all: { STAGE: 'dev' } },
			after: { tags_all: { STAGE: 'prod' } }
		});
		assert.deepEqual(changes, [{ key: 'tags_all.STAGE', before: 'dev', after: 'prod', isSensitive: false }]);
	});
});

describe('groupChangesByWorkspace', () => {
	it('groups a resource changed identically across all workspaces under "all"', () => {
		const resources = {
			'aws_instance.foo': {
				dev: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'b', isSensitive: false }] },
				prod: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'b', isSensitive: false }] }
			}
		};
		const result = groupChangesByWorkspace(resources, ['dev', 'prod']);
		assert.deepEqual(result, {
			all: [{
				resourceName: 'aws_instance.foo',
				action: 'UPDATED',
				changes: { ami: { before: 'a', after: 'b', isSensitive: false, affectedEnvCount: 2 } }
			}]
		});
	});

	it('preserves isSensitive when merging a resource changed identically across all workspaces', () => {
		const resources = {
			'aws_instance.foo': {
				dev: { action: 'UPDATED', changes: [{ key: 'password', before: 'old', after: 'new', isSensitive: true }] },
				prod: { action: 'UPDATED', changes: [{ key: 'password', before: 'old', after: 'new', isSensitive: true }] }
			}
		};
		const result = groupChangesByWorkspace(resources, ['dev', 'prod']);
		assert.equal(result.all[0].changes.password.isSensitive, true);
	});

	it('marks values as environment-specific when they differ across workspaces', () => {
		const resources = {
			'aws_instance.foo': {
				dev: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'dev-b' }] },
				prod: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'prod-b' }] }
			}
		};
		const result = groupChangesByWorkspace(resources, ['dev', 'prod']);
		assert.equal(result.all[0].changes.ami.before, 'a');
		assert.equal(result.all[0].changes.ami.after, '(environment-specific)');
	});

	it('keeps resources changed in only a subset of workspaces per-environment', () => {
		const resources = {
			'aws_instance.foo': {
				dev: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'b' }] }
			}
		};
		const result = groupChangesByWorkspace(resources, ['dev', 'prod']);
		assert.equal(result.all, undefined);
		assert.deepEqual(Object.keys(result), ['dev']);
		assert.equal(result.dev[0].resourceName, 'aws_instance.foo');
	});

	it('marks a change key as environment-specific if it is only present in some of the "all" workspaces', () => {
		const resources = {
			'aws_instance.foo': {
				dev: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'b' }, { key: 'tags.env', before: 'x', after: 'y' }] },
				prod: { action: 'UPDATED', changes: [{ key: 'ami', before: 'a', after: 'b' }] }
			}
		};
		const result = groupChangesByWorkspace(resources, ['dev', 'prod']);
		assert.equal(result.all[0].changes.ami.before, 'a');
		assert.equal(result.all[0].changes.ami.after, 'b');
		assert.equal(result.all[0].changes['tags.env'].before, '(environment-specific)');
		assert.equal(result.all[0].changes['tags.env'].after, '(environment-specific)');
	});
});
