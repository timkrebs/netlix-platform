# ─── EKS Cluster (small nodes for Vault workloads) ────────────────────────

module "eks" {
  source = "../../components/eks"

  cluster_name                         = "${var.project}-vault-${var.environment}"
  cluster_version                      = var.cluster_version
  vpc_id                               = local.vpc_id
  private_subnet_ids                   = local.private_subnet_ids
  node_instance_types                  = var.node_instance_types
  node_desired_size                    = var.node_desired_size
  node_min_size                        = var.node_min_size
  node_max_size                        = var.node_max_size
  environment                          = var.environment
  project                              = var.project
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
}

# ─── cert-manager (TLS certificates for Vault server) ────────────────────

module "cert_manager" {
  source = "../../components/cert-manager"
}

# ─── Vault Enterprise Server (5-node HA Raft on EKS) ─────────────────────

module "vault_server" {
  source = "../../components/vault-server"

  cluster_name           = module.eks.cluster_name
  environment            = var.environment
  project                = var.project
  vault_ent_license      = var.vault_ent_license
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.oidc_provider_url
  aws_region             = var.aws_region
  cert_manager_namespace = module.cert_manager.namespace
  domain                 = var.base_domain
  certificate_arn        = local.certificate_arn
}
