import json
from os import environ

GITHUB_ENV_PATH = environ.get('GITHUB_ENV')

variables = json.loads(environ.get('VARIABLES'))

with open(GITHUB_ENV_PATH, 'a', encoding="utf-8") as env_file:
	env_file.write('\n')

	for name, value in variables.items():
		env_file.write('TF_VAR_')
		env_file.write(name)
		env_file.write('=')
		env_file.write(value)
		env_file.write('\n')
