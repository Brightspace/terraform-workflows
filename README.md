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

Add a `preflight` environment by clicking `Settings` and then choosing `Environments` from the left-hand side.
Now, follow the steps below.

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

Now create an environment for each of your terraform envirionments/workspaces.
You do this by repeating the steps above, but use the terraform environment as the environment name.
i.e. If your workspace is `terraform/environments/prod/ca-central-1`, name the environment `prod/ca-central-1`

### iam-build-tokens

1. Create a GitHub Actions Hub-role for your repository to be used by PRs

```tf
module "your_repo_name_ro" {
  source = "../modules/githubactions/hub-role"

  repository = "{ your repo name }"

  assumable_role_arns = [
    # Your-Dev-Account-Name
    "{ terraform plan role in your dev account }",

    # Your-Prd-Account-Name
    "{ terraform plan role in your prd account }",

    # Dev-Terraform
    "arn:aws:iam::891724658749:role/github/Brightspace-{ your repo name }-tfstate-reader",
  ]
}
```

2. Create a GitHub Actions Hub-role for your environments to be used after merge
```tf
module "your_repo_name_rw" {
  source = "../modules/githubactions/hub-role"

  repository   = "{ your repo name }"
  environments = [
    "preflight",
    "{ your other environment names }",
  ]

  assumable_role_arns = [
    # Your-Dev-Account-Name
    "{ terraform apply role in your dev account }",

    # Your-Prd-Account-Name
    "{ terraform apply role in your prd account }",

    # Dev-Terraform
    "arn:aws:iam::891724658749:role/github/Brightspace-{ your repo name }-tfstate-manager",
  ]
}
```

### terraform-infrastructure

1. Configure Terraform state management for your repository

```tf
module "your_repo_name" {
  source = "../../../modules/tfstate-manager"

  github_repository = "{ your repo name }"

  reader_assuming_principal_arns = [

    # Hub Role (PRs)
    "arn:aws:iam::323258989788:role/hub-roles/github+Brightspace+{ your repo name }",

  ]

  manager_assuming_principal_arns = [

    # Hub Role (Post-Merge)
    "arn:aws:iam::323258989788:role/hub-roles/github+Brightspace+{ your repo name }+deploy",

  ]

  tfstate = local.tfstate
}
```

### Update your terraform

1. Remove all configuration from your s3 backend, if any.

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

### Add your workflow

```yaml
# terraform.yaml

name: Terraform

on:
  workflow_dispatch:
  pull_request:
  push:
    branches: main

env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  AWS_SESSION_TOKEN: ${{ secrets.AWS_SESSION_TOKEN }}

jobs:

  configure:
    name: Configure
    runs-on: [self-hosted, Linux, AWS]
    timeout-minutes: 1

    steps:
      - uses: Brightspace/terraform-workflows@configure/v2
        with:
          environment: dev/ca-central-1
          workspace_path: terraform/environments/dev/ca-central-1
          provider_role_arn_ro: "{ terraform plan role in your dev account }"
          provider_role_arn_rw: "{ terraform apply role in your dev account }"

      - uses: Brightspace/terraform-workflows@configure/v2
        with:
          environment: prod/ca-central-1
          workspace_path: terraform/environments/prod/ca-central-1
          provider_role_arn_ro: "{ terraform plan role in your prod account }"
          provider_role_arn_rw: "{ terraform apply role in your prod account }"

      - id: finish
        uses: Brightspace/terraform-workflows/finish@configure/v2

    outputs:
      environments: ${{ steps.finish.outputs.environments }}
      config: ${{ steps.finish.outputs.config }}


  plan:
    name: Plan
    runs-on: [self-hosted, Linux, AWS]
    timeout-minutes: 10

    environment: ${{ (github.event_name != 'pull_request' && 'preflight') || 'pr' }}

    needs: configure

    strategy:
      matrix:
        environment: ${{ fromJson(needs.configure.outputs.environments) }}

    steps:
    - uses: Brightspace/third-party-actions@actions/checkout

    - uses: Brightspace/terraform-workflows@plan/v2
      with:
        config: ${{ toJson(fromJson(needs.configure.outputs.config)[matrix.environment]) }}
        terraform_version: 1.0.3


  collect:
    name: Collect
    runs-on: [self-hosted, Linux, AWS]
    timeout-minutes: 2

    needs: plan

    if: ${{ github.event_name != 'pull_request' }}

    steps:
    - id: collect
      uses: Brightspace/terraform-workflows@collect/v2

    outputs:
      has_changes: ${{ steps.collect.outputs.has_changes }}
      changed: ${{ steps.collect.outputs.changed }}
      config: ${{ steps.collect.outputs.config }}


  apply:
    name: Apply
    runs-on: [self-hosted, Linux, AWS]
    timeout-minutes: 10

    needs: collect

    if: ${{ needs.collect.outputs.has_changes == 'true' }}

    strategy:
      matrix:
        environment: ${{ fromJson(needs.collect.outputs.changed) }}

    environment: ${{ matrix.environment }}
    concurrency: ${{ matrix.environment }}

    steps:
    - uses: Brightspace/third-party-actions@actions/checkout

    - uses: Brightspace/terraform-workflows@apply/v2
      with:
        config: ${{ toJson(fromJson(needs.collect.outputs.config)[matrix.environment]) }}

```
