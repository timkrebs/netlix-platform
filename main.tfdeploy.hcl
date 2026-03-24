# ─── Identity tokens (OIDC — no static credentials) ───────────────────────

identity_token "aws" {
  audience = ["aws.workload.identity"]
}

identity_token "hcp" {
  audience = ["hashicorp.com"]
}

# ─── Variable set store (Vault token) ────────────────────────────────────

store "varset" "netlix-vault" {
  id       = "varset-DygE5qeNYGw62Gxs"
  category = "terraform"
}

# ─── Deployment: dev ───────────────────────────────────────────────────────

deployment "dev" {
  inputs = {
    aws_identity_token  = identity_token.aws.jwt
    aws_region          = "eu-central-1"
    role_arn            = "arn:aws:iam::173003892479:role/tfc-netlix-dev"
    hcp_project_id      = "ebae3a61-f614-4427-bed4-9d99817dea57"
    vault_cluster_id    = "netlix-vault"
    vault_address       = "https://netlix-vault-public-vault-7ebc141d.dffa8084.z1.hashicorp.cloud:8200"
    vault_token         = store.varset.netlix-vault.vault_token
    vpc_cidr            = "10.0.0.0/16"
    azs                 = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    cluster_name        = "netlix-dev"
    cluster_version     = "1.31"
    node_instance_types = ["m6i.large"]
    node_desired_size   = 3
    node_min_size       = 2
    node_max_size       = 5
    db_instance_class   = "db.t4g.medium"
    db_name             = "netlix"
    db_engine_version   = "16.6"
    github_org          = "timkrebs"
    github_pat            = "placeholder-replace-with-vault-dynamic-secret"
    vault_admin_username  = store.varset.netlix-vault.vault_admin_username
    vault_admin_password  = store.varset.netlix-vault.vault_admin_password
    environment           = "dev"
    project             = "netlix"
    default_tags        = {}
  }
}

# ─── Deployment: staging ───────────────────────────────────────────────────

deployment "staging" {
  inputs = {
    aws_identity_token  = identity_token.aws.jwt
    aws_region          = "eu-central-1"
    role_arn            = "arn:aws:iam::173003892479:role/tfc-netlix-staging"
    hcp_project_id      = "ebae3a61-f614-4427-bed4-9d99817dea57"
    vault_cluster_id    = "netlix-vault"
    vault_address       = "https://netlix-vault-public-vault-7ebc141d.dffa8084.z1.hashicorp.cloud:8200"
    vault_token         = store.varset.netlix-vault.vault_token
    vpc_cidr            = "10.1.0.0/16"
    azs                 = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    cluster_name        = "netlix-staging"
    cluster_version     = "1.31"
    node_instance_types = ["m6i.large"]
    node_desired_size   = 3
    node_min_size       = 3
    node_max_size       = 6
    db_instance_class   = "db.m6i.large"
    db_name             = "netlix"
    db_engine_version   = "16.6"
    github_org          = "timkrebs"
    github_pat            = "placeholder-replace-with-vault-dynamic-secret"
    vault_admin_username  = store.varset.netlix-vault.vault_admin_username
    vault_admin_password  = store.varset.netlix-vault.vault_admin_password
    environment           = "staging"
    project             = "netlix"
    default_tags        = {}
  }
}
