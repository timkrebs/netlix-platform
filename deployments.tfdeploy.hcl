# ─── Identity tokens (OIDC — no static credentials) ───────────────────────

identity_token "aws" {
  audience = ["aws.workload.identity"]
}

# ─── Variable set stores ──────────────────────────────────────────────────

# Vault secrets varset (Enterprise license, root token, GitHub PAT, etc.)
store "varset" "netlix-vault" {
  id       = "varset-KzPCKUxZHwNvVQ4Z"
  category = "terraform"
}

# ─── Deployment: dev ───────────────────────────────────────────────────────

deployment "dev" {
  inputs = {
    # Authentication
    aws_identity_token = identity_token.aws.jwt
    aws_region         = "eu-central-1"
    role_arn           = "arn:aws:iam::173003892479:role/tfc-netlix-dev"

    # Vault Enterprise
    vault_ent_license = store.varset.netlix-vault.vault_ent_license
    vault_root_token  = store.varset.netlix-vault.vault_root_token

    # Networking
    vpc_cidr = "10.0.0.0/16"
    azs      = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

    # DNS
    base_domain     = "netlix.dev"
    route53_zone_id = "Z03825243OZJVWRUDJ5T"

    # EKS
    cluster_name        = "netlix-dev"
    cluster_version     = "1.31"
    node_instance_types = ["m6i.large"]
    node_desired_size   = 3
    node_min_size       = 2
    node_max_size       = 5
    cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # dev: open for debugging — restrict in staging/prod

    # RDS
    db_instance_class = "db.t4g.medium"
    db_name           = "netlix"
    db_engine_version = "16.6"

    # Application
    github_org = "timkrebs"
    github_pat = store.varset.netlix-vault.github_pat

    alert_email = ""

    # Metadata
    environment           = "dev"
    project               = "netlix"
    tfc_organization_name = "tim-krebs-org"
    default_tags          = {}
  }
}

# ─── Deployment: staging ────────────────────────────────────────────────────

deployment "staging" {
  inputs = {
    # Authentication
    aws_identity_token = identity_token.aws.jwt
    aws_region         = "eu-central-1"
    role_arn           = "arn:aws:iam::173003892479:role/tfc-netlix-staging"

    # Vault Enterprise
    vault_ent_license = store.varset.netlix-vault.vault_ent_license
    vault_root_token  = store.varset.netlix-vault.vault_root_token

    # Networking
    vpc_cidr = "10.1.0.0/16"
    azs      = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

    # DNS
    base_domain     = "netlix.dev"
    route53_zone_id = "Z051580832J77K2X4KU7U"

    # EKS
    cluster_name        = "netlix-staging"
    cluster_version     = "1.31"
    node_instance_types = ["m6i.xlarge"]
    node_desired_size   = 3
    node_min_size       = 3
    node_max_size       = 6
    cluster_endpoint_public_access_cidrs = [] # staging: private-only endpoint (production-like)

    # RDS
    db_instance_class = "db.t4g.large"
    db_name           = "netlix"
    db_engine_version = "16.6"

    # Application
    github_org = "timkrebs"
    github_pat = store.varset.netlix-vault.github_pat

    alert_email = ""

    # Metadata
    environment           = "staging"
    project               = "netlix"
    tfc_organization_name = "tim-krebs-org"
    default_tags          = {}
  }
}

