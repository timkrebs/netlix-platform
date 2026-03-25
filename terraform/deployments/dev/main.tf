# ─── Networking ────────────────────────────────────────────────────────────

module "networking" {
  source = "../../components/networking"

  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
  environment = var.environment
  project     = var.project
}

# ─── HVN Peering ──────────────────────────────────────────────────────────

module "hvn_peering" {
  source = "../../components/hvn-peering"

  hvn_id                  = var.hvn_id
  peer_vpc_id             = module.networking.vpc_id
  peer_account_id         = module.networking.vpc_owner_id
  peer_vpc_region         = var.aws_region
  vpc_cidr                = var.vpc_cidr
  private_route_table_ids = module.networking.private_route_table_ids
  environment             = var.environment
  project                 = var.project
}

# ─── EKS ──────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../components/eks"

  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  environment         = var.environment
  project             = var.project
}

# ─── RDS ──────────────────────────────────────────────────────────────────

module "rds" {
  source = "../../components/rds"

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  db_instance_class  = var.db_instance_class
  db_name            = var.db_name
  db_engine_version  = var.db_engine_version
  eks_security_group = module.eks.cluster_security_group_id
  hvn_cidr_block     = module.hvn_peering.hvn_cidr_block
  environment        = var.environment
  project            = var.project
}

# ─── Vault Config ─────────────────────────────────────────────────────────

module "vault_config" {
  source = "../../components/vault-config"

  vault_cluster_id      = var.vault_cluster_id
  vault_address         = var.vault_address
  eks_cluster_endpoint  = module.eks.cluster_endpoint
  eks_cluster_ca        = module.eks.cluster_ca_certificate
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_provider_url = module.eks.oidc_provider_url
  rds_endpoint          = module.rds.endpoint
  rds_port              = module.rds.port
  rds_admin_username    = module.rds.admin_username
  rds_admin_password    = module.rds.admin_password
  db_name               = var.db_name
  github_org            = var.github_org
  github_pat            = var.github_pat
  pki_allowed_domains   = ["netlix.dev", "netlix.internal", "svc.cluster.local"]
  environment           = var.environment

  depends_on = [module.hvn_peering]
}

# ─── VSO ──────────────────────────────────────────────────────────────────

module "vso" {
  source = "../../components/vso"

  vault_address        = module.vault_config.vault_public_endpoint
  vault_namespace      = module.vault_config.vault_namespace
  kubernetes_auth_path = module.vault_config.kubernetes_auth_path
}

# ─── ArgoCD ───────────────────────────────────────────────────────────────

module "argocd" {
  source = "../../components/argocd"

  gitops_repo_url  = "https://github.com/${var.github_org}/netlix-gitops.git"
  target_namespace = "netlix"
}
