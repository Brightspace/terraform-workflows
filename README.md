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

Within the content, the `provider_role_arn` specified will be the arn of the role, not just the role name.

Each region that you have defined for your workflows will also need to be added as blocks.  For example,
in the content below, only `dev/ca-central-1` and `prod/ca-central-1` are defined.

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
        - provider_role_arn_ro: "{ terraform plan role in your dev account }"
          provider_role_arn_rw: "{ terraform apply role in your dev account }"
          workspaces:
            - environment: dev/us-east-1
              path: terraform/environments/dev/us-east-1

        - provider_role_arn_ro: "{ terraform plan role in your prod account }"
          provider_role_arn_rw: "{ terraform apply role in your prod account }"
          workspaces:
            - environment: prod/ca-central-1
              path: terraform/environments/prod/ca-central-1
            - environment: prod/us-east-1
              path: terraform/environments/prod/us-east-1
```
