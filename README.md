# GitHub Actions Terraform Workflows

## What is this repo?
The `terraform-workflows` repo is an attempt to provide a consistent and secure means for all projects within
D2L to perform the many workflow tasks they have in common.  It aims to provide instructions on how you can
structure your workflows to give minimum permissions to all roles, and to offer a flexible but consistent
structure to your terraform usage.

## Setup

### Repository Environments

In your own repository you will need to create an environment for all activities that
take place prior to commits with your repositories.

Add a `preflight` environment by clicking `Settings` and then choosing `Environments` from the left-hand side
and follow the steps below.

1. Create your environment
  * Click `New Environment`
  * Enter `preflight` and click `Configure Environment`.
2. Add your main branch to the environment
  * From the configuration screen, Click `All branches` and choose `Selected branches`
  * Click `Add deployment branch rule`
  * Enter the name of your main branch, e.g. `main`, and click `Add rule`.
3. Save this environment by clicking `Save protection rules`.

Now create an environment for each of your terraform envirionments/workspaces.
You do this by following the steps below, but use the terraform environment as the environment name.
i.e. If your workspace is `terraform/environments/prod/ca-central-1`, name the environment `prod/ca-central-1`

1. Create your environment
  * Click `New Environment`
  * Enter your environment name and click `Configure Environment`.
2. Add your main branch to the environment
  * From the configuration screen, Click `All branches` and choose `Selected branches`
  * Click `Add deployment branch rule`
  * Enter the name of your main branch, e.g. `main`, and click `Add rule`.
3. Add required reviewers for this environment
  * Check the `Required reviewers` checkbox.
  * In the box that appears, add the appropriate set of reviewers that can approve your deployments.
4. Save this environment by clicking `Save protection rules`.

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

Within the content, the `provider_role_arn_{ro,rw}` specified will be the arn of the role, not just the role name.

Each region that you have defined for your workflows will also need to be added as worksapces.  For example,
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
    uses: Brightspace/terraform-workflows/.github/workflows/workflow.yml@v3
    secrets: inherit
    with:
      terraform_version: 1.2.1
      config: |
        # Dev-Project Account
        - provider_role_arn_ro: "{ terraform plan role in your dev account }"
          provider_role_arn_rw: "{ terraform apply role in your dev account }"
          workspaces:
            - environment: dev/us-east-1
              path: terraform/environments/dev/us-east-1

        # Prd-Project Account
        - provider_role_arn_ro: "{ terraform plan role in your prod account }"
          provider_role_arn_rw: "{ terraform apply role in your prod account }"
          workspaces:
            - environment: prod/ca-central-1
              path: terraform/environments/prod/ca-central-1
            - environment: prod/us-east-1
              path: terraform/environments/prod/us-east-1
```

#### Inputs

##### `config` (`Account[]`)

**Required**.
The `config` input is a YAML string which describes your terraform workspaces.
The workspaces are grouped by account in order to de-duplicate some shared settings for the common scenario of dev/prod accounts.
The root of the YAML document should be an array of `Account` objects.

###### `Account.provider_role_arn_ro` (`string`)

**Required**.
The read-only role to use when performing terraform plans for pull requests in the account.
Likely named `terraform-plan` and thus of the form `arn:aws:iam::{accountId}:role/terraform-plan`.

###### `Account.provider_role_arn_rw` (`string`)

**Required**.
The role to use when performing terraform plan and applies for merged pull requests in the account.
Likely named `terraform-apply` and thus of the form `arn:aws:iam::{accountId}:role/terraform-apply`.

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
The path to the terraform workspace within your resository.

###### `Workspace.provider_role_tfvar` (`string`)

**Optional**.
The terraform variable to set when specifying the provider role ARN.
Defaults to the configured account value else to `terraform_role_arn`.

---

##### `default_branch` (`string`)

**Optional**.
When running on the main branch, the workflow asserts that it is running on the latest commit so old builds aren't accidently re-run and applied.
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


## Migrating from v2

If migrating from v2 of terraform-workflows, then when possible v3's [reusable-workflow](#add-your-workflow) should be preferred.
For builds that are not yet terraform-only and need additional customization the individual actions are still available; however,
referencing these actions has changed:

```diff
- uses: Brightspace/terraform-workflows@configure/v2
+ uses: Brightspace/terraform-workflows/actions/configure@v3

- uses: Brightspace/terraform-workflows/finish@configure/v2
+ uses: Brightspace/terraform-workflows/actions/configure/finish@v3

- uses: Brightspace/terraform-workflows@plan/v2
+ uses: Brightspace/terraform-workflows/actions/plan@v3

- uses: Brightspace/terraform-workflows@apply/v2
+ uses: Brightspace/terraform-workflows/actions/apply@v3
```
