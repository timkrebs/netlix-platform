# ─── Project ──────────────────────────────────────────────────────────────

data "tfe_project" "this" {
  name         = var.tfc_project_name
  organization = var.tfc_organization
}

# ─── Workspace definitions ────────────────────────────────────────────────

locals {
  workspace_configs = {
    network = {
      working_directory = "terraform/workspaces/network"
      description       = "Shared networking: VPC, subnets, NAT, Route53, ACM"
    }
    vault-cluster = {
      working_directory = "terraform/workspaces/vault-cluster"
      description       = "Vault EKS cluster (small nodes) + Vault Enterprise HA"
    }
    app-cluster = {
      working_directory = "terraform/workspaces/app-cluster"
      description       = "App EKS cluster + ALB + ArgoCD + VSO + Vault config + monitoring"
    }
  }

  # Flatten environment x workspace into individual workspace resources
  workspaces = {
    for pair in flatten([
      for env_name, env in var.environments : [
        for ws_name, ws in local.workspace_configs : {
          key               = "netlix-${ws_name}-${env_name}"
          ws_name           = ws_name
          env_name          = env_name
          working_directory = ws.working_directory
          description       = ws.description
          vcs_branch        = env.vcs_branch
          role_arn          = env.role_arn
        }
      ]
    ]) : pair.key => pair
  }
}

resource "tfe_workspace" "this" {
  for_each = local.workspaces

  name              = each.key
  organization      = var.tfc_organization
  project_id        = data.tfe_project.this.id
  description       = "${each.value.description} (${each.value.env_name})"
  working_directory = each.value.working_directory
  terraform_version = "~> 1.9"
  auto_apply        = false
  queue_all_runs    = false

  # Tags must match the `tags = [...]` selector in each workspace's
  # versions.tf cloud block, otherwise local `terraform plan` cannot
  # resolve the workspace via tag-based selection.
  tag_names = ["netlix", each.value.ws_name]

  dynamic "vcs_repo" {
    for_each = var.enable_vcs ? [1] : []
    content {
      identifier     = var.github_repository
      branch         = each.value.vcs_branch
      oauth_token_id = var.github_oauth_token_id
    }
  }
}

# ─── Remote state sharing ────────────────────────────────────────────────
# network shares outputs with vault-cluster and app-cluster.
# vault-cluster shares outputs with app-cluster.

resource "tfe_workspace_settings" "network" {
  for_each = var.environments

  workspace_id = tfe_workspace.this["netlix-network-${each.key}"].id
  remote_state_consumer_ids = [
    tfe_workspace.this["netlix-vault-cluster-${each.key}"].id,
    tfe_workspace.this["netlix-app-cluster-${each.key}"].id,
  ]
}

resource "tfe_workspace_settings" "vault_cluster" {
  for_each = var.environments

  workspace_id = tfe_workspace.this["netlix-vault-cluster-${each.key}"].id
  remote_state_consumer_ids = [
    tfe_workspace.this["netlix-app-cluster-${each.key}"].id,
  ]
}

# ─── Dynamic provider credentials (AWS OIDC) ─────────────────────────────

resource "tfe_variable" "aws_provider_auth" {
  for_each = local.workspaces

  key          = "TFC_AWS_PROVIDER_AUTH"
  value        = "true"
  category     = "env"
  workspace_id = tfe_workspace.this[each.key].id
  description  = "Enable dynamic provider credentials for AWS"
}

resource "tfe_variable" "aws_run_role_arn" {
  for_each = local.workspaces

  key          = "TFC_AWS_RUN_ROLE_ARN"
  value        = each.value.role_arn
  category     = "env"
  workspace_id = tfe_workspace.this[each.key].id
  description  = "AWS IAM role ARN for OIDC assume-role"
}

# ─── Workspace variables (environment + project) ─────────────────────────

resource "tfe_variable" "environment" {
  for_each = local.workspaces

  key          = "environment"
  value        = each.value.env_name
  category     = "terraform"
  workspace_id = tfe_workspace.this[each.key].id
  description  = "Environment name"
}

resource "tfe_variable" "project" {
  for_each = local.workspaces

  key          = "project"
  value        = "netlix"
  category     = "terraform"
  workspace_id = tfe_workspace.this[each.key].id
  description  = "Project name"
}

# ─── Variable set attachment (vault secrets) ──────────────────────────────
# Attach the existing netlix-vault varset to vault-cluster and app-cluster

locals {
  varset_workspaces = {
    for key, ws in local.workspaces : key => ws
    if ws.ws_name != "network"
  }
}

resource "tfe_workspace_variable_set" "vault_secrets" {
  for_each = local.varset_workspaces

  variable_set_id = var.vault_varset_id
  workspace_id    = tfe_workspace.this[each.key].id
}

# ─── Run triggers (dependency chain) ─────────────────────────────────────
# network -> vault-cluster, network -> app-cluster

locals {
  run_triggers = {
    for pair in flatten([
      for env_name, env in var.environments : [
        {
          key       = "vault-cluster-after-network-${env_name}"
          workspace = "netlix-vault-cluster-${env_name}"
          source    = "netlix-network-${env_name}"
        },
        {
          key       = "app-cluster-after-network-${env_name}"
          workspace = "netlix-app-cluster-${env_name}"
          source    = "netlix-network-${env_name}"
        },
      ]
    ]) : pair.key => pair
  }
}

resource "tfe_run_trigger" "this" {
  for_each = local.run_triggers

  workspace_id  = tfe_workspace.this[each.value.workspace].id
  sourceable_id = tfe_workspace.this[each.value.source].id
}

# ─── Sentinel policy set ─────────────────────────────────────────────────

resource "tfe_policy_set" "sentinel" {
  count = var.enable_vcs ? 1 : 0

  name         = "netlix-sentinel"
  organization = var.tfc_organization
  kind         = "sentinel"

  vcs_repo {
    identifier     = var.github_repository
    branch         = "main"
    oauth_token_id = var.github_oauth_token_id
  }

  policies_path = "sentinel"

  workspace_ids = [for ws in tfe_workspace.this : ws.id]
}
