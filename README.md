# GitHub Actions Terraform Workflows

## Setup

### Repository Environments

1. Create an environment called `preflight`.
  * Add a _Selected brances_ rule to _Deployment branches_, restricting it to `main`
2. Create an environment for each of your terraform environments/worksapces
  * e.g. If your workspace is `terraform/environments/prod/ca-central-1`, name the environment `prod/ca-central-1`
  * Add a _Selected brances_ rule to _Deployment branches_, restricting it to `main`
  * Add at least one team or person to _Required reviewers_

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
      - uses: Brightspace/terraform-workflows@configure/v1
        with:
          environment: dev/ca-central-1
          workspace_path: terraform/environments/dev/ca-central-1
          provider_role_arn_ro: "{ terraform plan role in your dev account }"
          provider_role_arn_rw: "{ terraform apply role in your dev account }"

      - uses: Brightspace/terraform-workflows@configure/v1
        with:
          environment: prod/ca-central-1
          workspace_path: terraform/environments/prod/ca-central-1
          provider_role_arn_ro: "{ terraform plan role in your prod account }"
          provider_role_arn_rw: "{ terraform apply role in your prod account }"

      - id: finish
        uses: Brightspace/terraform-workflows/finish@configure/v1

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

    - uses: Brightspace/terraform-workflows@plan/v1
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
      uses: Brightspace/terraform-workflows@collect/v1

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

    - uses: Brightspace/terraform-workflows@apply/v1
      with:
        config: ${{ toJson(fromJson(needs.collect.outputs.config)[matrix.environment]) }}

```
