# ─── Current caller identity (for EKS admin access) ──────────────────────

data "aws_caller_identity" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

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
  additional_admin_arns                = [data.aws_iam_session_context.current.issuer_arn]
}

# ─── ExternalDNS (creates vault.dev.netlix.dev Route53 record) ────────────

module "external_dns" {
  source = "../../components/external-dns"

  cluster_name          = module.eks.cluster_name
  domain                = var.base_domain
  zone_id               = local.zone_id
  external_dns_role_arn = module.eks.external_dns_role_arn
}

# ─── cert-manager (TLS certificates for Vault server) ────────────────────

module "cert_manager" {
  source = "../../components/cert-manager"
}

# Wait for cert-manager CRDs to be registered in the Kubernetes API.
# The Helm release completes when pods are ready, but CRD API registration
# is asynchronous and takes a few seconds longer.
resource "time_sleep" "wait_for_cert_manager_crds" {
  depends_on      = [module.cert_manager]
  create_duration = "30s"
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

  depends_on = [time_sleep.wait_for_cert_manager_crds]
}
