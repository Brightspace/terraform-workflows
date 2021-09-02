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

Note that as a side-effect of a limitation there will be an environment called `pr` created in your
`Environments` list the first time it is referenced by terraform.  This is normal and should be left alone.

### iam-build-tokens

The [iam-build-tokens](https://github.com/Brightspace/iam-build-tokens) repository contains the
registry of the roles that require access to company resources.  These tokens enable the ability
to read/write/update systems like the build state, etc.

You must add roles for your workflows to use to this repository.

Go to the `terraform/roles` folder in the repository and add a terraform file that corresponds
to your repository.
i.e. - If your repository is `Brightspace/webdav`, add a `terraform/roles/webdav.tf` file.

In this file you will need two modules.  These modules will document the roles that require
build tokens.  Be sure to include all roles that will be used in your workflows that need
access to systems.  For example, if you have a separate workflow that publishes containers
to ECR, be sure to include that role in the list.

The roles you define here should be roles that are defined for read-only access.

The repository name you use is the portion that comes after the `Brightspace/`.
i.e. - If your repository is `Brightspace/webdav`, use `repository = "webdav"`.

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
    "arn:aws:iam::891724658749:role/github/Brightspace+{ your repo name }+tfstate-reader",
  ]
}
```

The roles defined here should be read-write access roles. (Please note the difference
in module name.)
Be sure that the listed environments matches the environments you created earlier.
You will know it is working when you check your Environments and see a green lock
icon with `1 secret` appear next to each environment.  If you have defined an
environment that does not get this added, you need to double check your list of
environments below.

2. Create a GitHub Actions Hub-role for your environments to be used after merge
```tf
module "your_repo_name_rw" {
  source = "../modules/githubactions/hub-role"

  repository   = "{ your repo name }"
  environments = [
    "preflight",
    "{ your other dev and prod environment names }",
  ]

  assumable_role_arns = [
    # Your-Dev-Account-Name
    "{ terraform apply role in your dev account }",

    # Your-Prd-Account-Name
    "{ terraform apply role in your prd account }",

    # Dev-Terraform
    "arn:aws:iam::891724658749:role/github/Brightspace+{ your repo name }+tfstate-manager",
  ]
}
```

After the PR is merged, you will need to approve the workflow to have the changes deployed.
GitHub will also remind you of this fact on your PR with a link to instructions on how to apply the changes.
Your workflow will be listed on [CircleCI](https://app.circleci.com/pipelines/github/Brightspace/iam-build-tokens).

### terraform-infrastructure

The [terraform-infrastructure](https://github.com/Brightspace/terraform-infrastructure) repository
consolidates the state for all terraform in one place.  Adding your repository here will enable
it to store state in the shared terraform state.

Go to the `terraform/environments/dev-terraform` folder in the repository and add a terraform file that corresponds
to your repository.
i.e. - If your repository is `Brightspace/webdav`, add a `webdav.tf` file.

Don't worry about the folders that your file is in, those are relevant to the account and location of the state,
rather than being related to anything to do with your own repository terraform state.

The `github_repository` name you use is the portion that comes after the `Brightspace/`.
i.e. - If your repository is `Brightspace/webdav`, use `github_repository = "webdav"`.

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

### Update any exsting deployment roles

If you have any exsting roles being used by your deployment infrastructure these will
need to have their trust relationship policy updated.

Navigate to IAM, find your role used for deployment, click over to the `Trust relationships` tab
and click `Edit trust relationship`.

Be sure to make this change in both your Dev and Prod accounts.

Apply the following change:
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::323258989788:role/hub-roles/github+Brightspace+{ your repo name }+deploy",
          "arn:aws:iam::323258989788:role/hub-roles/github+Brightspace+{ your repo name }"
        ]
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }
  ]
}
```

### Add your workflow

Now the Terraform workflow can be added to the repository.  Create the `.github/workflows/terraform.yaml` in
your repository with the following content.

Within the content, the `provider_role_arn` specified will be the arn of the role, not just the role name.

Each region that you have defined for your workflows will also need to be added as blocks.  For example,
in the content below, only `dev/ca-central-1` and `prod/ca-central-1` are defined.

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
  TERRAFORM_VERSION: 1.0.5

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


  plan_pr:
    name: Plan [PR]
    runs-on: [self-hosted, Linux, AWS]
    timeout-minutes: 10

    if: ${{ github.event_name == 'pull_request' }}

    needs: configure

    strategy:
      fail-fast: false
      matrix:
        environment: ${{ fromJson(needs.configure.outputs.environments) }}

    steps:
    - uses: Brightspace/third-party-actions@actions/checkout

    - uses: Brightspace/terraform-workflows@plan/v2
      with:
        config: ${{ toJson(fromJson(needs.configure.outputs.config)[matrix.environment]) }}
        terraform_version: ${{ env.TERRAFORM_VERSION }}


  plan:
    name: Plan
    runs-on: [self-hosted, Linux, AWS]
    timeout-minutes: 10

    if: ${{ github.event_name != 'pull_request' }}
    environment: preflight

    needs: configure

    strategy:
      fail-fast: false
      matrix:
        environment: ${{ fromJson(needs.configure.outputs.environments) }}

    steps:
    - uses: Brightspace/third-party-actions@actions/checkout

    - uses: Brightspace/terraform-workflows@plan/v2
      with:
        config: ${{ toJson(fromJson(needs.configure.outputs.config)[matrix.environment]) }}
        terraform_version: ${{ env.TERRAFORM_VERSION }}


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
      fail-fast: false
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
