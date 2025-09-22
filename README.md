# GitHub Actions Terraform Workflows

## What is this repo?
The `terraform-workflows` repo is an attempt to provide a consistent and secure means for all projects within
D2L to perform the many workflow tasks they have in common.  It aims to provide instructions on how you can
structure your workflows to give minimum permissions to all roles, and to offer a flexible but consistent
structure to your terraform usage.

## Setup

### repo-settings

Head over to repo-settings and follow the the [terraform instructions](https://github.com/Brightspace/repo-settings/blob/main/docs/terraform.md).

### Update your terraform

1. Remove all configuration from your s3 backend, if any and replace it with the following.

```tf
terraform {
  backend "s3" {}
}
```

2. Add a variable for and use it as input to your primary aws provider role_arn

```tf
variable "terraform_role_arn" {
  type = string
}

provider "aws" {
  // ...

  assume_role {
    role_arn = var.terraform_role_arn
  }
}
```

3. (Optional) Update all artifacts paths to be under `${path.root}/.artifacts/`

```tf
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/index.js"
  output_path = "${path.root}/.artifacts/lambda_package.zip"
}
```


### Add your workflow

Now the Terraform workflow can be added to the repository.  Create the `.github/workflows/terraform.yml` in
your repository with the following content.

Each region that you have defined for your workflows will also need to be added as workspaces.  For example,
in the content below, only `dev/us-east-1`, `prod/ca-central-1` and `prod/us-east-1` are defined.

```yaml
# .github/workflows/terraform.yml

name: Terraform

on:
  workflow_dispatch:
  pull_request:
  push:
    branches: main

jobs:

  terraform:
    uses: Brightspace/terraform-workflows/.github/workflows/workflow.yml@v4
    secrets: inherit
    with:
      terraform_version: 1.2.1
      config: |
        [{
          // Dev-Project Account
          "account_id": "< your dev account ID >",
          "workspaces": [{
            "environment": "dev/us-east-1",
            "path": "terraform/environments/dev/us-east-1"
          }]
        }, {
          // Prd-Project Account
          "account_id": "< your prod account ID >",
          "workspaces": [{
            "environment": "prod/ca-central-1",
            "path": "terraform/environments/prod/ca-central-1"
          }, {
            "environment": "prod/us-east-1",
            "path": "terraform/environments/prod/us-east-1"
          }]
        }]
```

#### Inputs

##### `config` (`Account[]`)

**Required**.
The `config` input is a JSON (with comments) string which describes your terraform workspaces.
The workspaces are grouped by account in order to de-duplicate some shared settings for the common scenario of dev/prod accounts.
The root of the document should be an array of `Account` objects.

###### `Account.account_id` (`string`)

**Recommended**.
The 12 digit ID of the account where Terraform will be run.
Required unless both `Account.provider_role_arn_ro` and `Account.provider_role_arn_rw` are provided (see below).

###### `Account.provider_role_arn_ro` (`string`)

**Optional**.
The read-only role to use when performing terraform plans for pull requests in the account.
Only needed if you do not wish to use the auto provisioned Terraform plan role.
Required if `Account.account_id` isn't provided.

###### `Account.provider_role_arn_rw` (`string`)

**Optional**.
The role to use when performing terraform plan and applies for merged pull requests in the account.
Only needed if you do not wish to use the auto provisioned Terraform apply role.
Required if `Account.account_id` isn't provided.

###### `Account.provider_role_tfvar` (`string`)

**Optional**.
The terraform variable to set when specifying the provider role ARN.
Defaults to `terraform_role_arn`.

###### `Account.workspaces` (`Workspace[]`)

**Required**.
An array of `Workspace` objects describing the targetted environments in the account.

###### `Workspace.environment` (`string`)

**Required**.
The name of the environment that describes the targetted resources (e.g. `dev/us-east-1` or `prd-project/ca-central-1`).
MUST match a configured GitHub environment.
MUST be unique across all accounts and workspaces.

###### `Workspace.path` (`string`)

**Required**.
The path to the terraform workspace within your repository.

###### `Workspace.provider_role_tfvar` (`string`)

**Optional**.
The terraform variable to set when specifying the provider role ARN.
Defaults to the configured account value else to `terraform_role_arn`.

---

##### `default_branch` (`string`)

**Optional**.
When running on the main branch, the workflow asserts that it is running on the latest commit so old builds aren't accidentally re-run and applied.
If you run into this restriction when trying to revert to an old state by running an old build, you should open a PR reverting any source changes and merge that instead.
Defaults to `main`.

---

##### `refresh_on_pr` (`boolean`)

**Optional**.
Whether to refresh terraform state when running terraform plans on a pull request.
Defaults to `true`.

---

##### `terraform_version` (`string`)

**Required**.
The version of terraform to install and use (e.g. `1.2.1`).

---

##### `require_lockfile` (`boolean`)

**Optional**
Whether the Terraform [lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock) .terraform.lock.hcl must declare all providers in the workspace.
Defaults to `false`.

---

##### `slack_channel` (`string`)

**Optional**.
If specified, sends notifications to the Slack channel at the end of Terraform Plan and Apply jobs.
You must also add the [GitHub Actions](https://d2l.slack.com/apps/A04BR0NCZAS-github-actions) Slack app to the channel's integrations.

## Terraform Format

This is used to ensure formatting on PRs. It is not included in the standard workflow.
It will fail if `terraform fmt` has any changes and create a PR with the changes to fix formatting with your PR as the target.
The formatting is recursive, so you can use one action for the entire repo.

Sample yaml file:
```yaml
# .github/workflows/terraform-format.yml
name: terraform-format

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-format.yml'
jobs:
  call-workflow:
    uses: Brightspace/terraform-workflows/.github/workflows/format.yml@v4
    with:
      terraform_version: 0.14.4
      base_path: '.'


```

#### Inputs
##### `terraform_version` (`string`)

**Required**.
The version of terraform to install and use (e.g. `1.2.1`).

##### `base_path` (`string`)

**Required**.
The path from which terraform fmt will run (e.g. `terraform` or `.`)


## Migrating from v2

If migrating from v2 of terraform-workflows, then when possible v3's [reusable-workflow](#add-your-workflow) should be preferred.
For builds that are not yet terraform-only and need additional customization the individual actions are still available; however,
referencing these actions has changed:

```diff
- uses: Brightspace/terraform-workflows@configure/v2
+ uses: Brightspace/terraform-workflows/actions/configure@v4

- uses: Brightspace/terraform-workflows/finish@configure/v2
+ uses: Brightspace/terraform-workflows/actions/configure/finish@v4

- uses: Brightspace/terraform-workflows@plan/v2
+ uses: Brightspace/terraform-workflows/actions/plan@v4

- uses: Brightspace/terraform-workflows@collect/v2
+ uses: Brightspace/terraform-workflows/actions/collect@v4

- uses: Brightspace/terraform-workflows@apply/v2
+ uses: Brightspace/terraform-workflows/actions/apply@v4
```
