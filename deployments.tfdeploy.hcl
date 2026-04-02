# ─── Identity tokens (OIDC — no static credentials) ───────────────────────

identity_token "aws" {
  audience = ["aws.workload.identity"]
}

# ─── Variable set stores ──────────────────────────────────────────────────

store "varset" "netlix-vault" {
  id       = "varset-4NoitsJtiV3MSVcg"
  category = "terraform"
}

store "varset" "netlix-hcp" {
  id       = "varset-N9WxeF7Jw3G6LhdD"
  category = "terraform"
}

# ─── Deployment: dev ───────────────────────────────────────────────────────

deployment "dev" {
  inputs = {
    # Authentication
    aws_identity_token = identity_token.aws.jwt
    aws_region         = "eu-central-1"
    role_arn           = "arn:aws:iam::173003892479:role/tfc-netlix-dev"
    hcp_project_id     = "ebae3a61-f614-4427-bed4-9d99817dea57"
    hcp_client_id      = store.varset.netlix-hcp.hcp_client_id
    hcp_client_secret  = store.varset.netlix-hcp.hcp_client_secret
    vault_cluster_id   = "netlix-vault"
    vault_address      = "https://netlix-vault-public-vault-7ebc141d.dffa8084.z1.hashicorp.cloud:8200"
    vault_token        = store.varset.netlix-vault.vault_token
    hvn_id             = "hvn"

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
    github_pat = "placeholder-replace-with-vault-dynamic-secret"

    # Metadata
    environment           = "dev"
    project               = "netlix"
    tfc_organization_name = "tim-krebs-org"
    default_tags          = {}
  }
}

