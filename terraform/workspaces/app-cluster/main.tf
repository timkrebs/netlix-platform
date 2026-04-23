# ─── Current caller identity (for EKS admin access) ──────────────────────

data "aws_caller_identity" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# ─── EKS Cluster (app workloads) ──────────────────────────────────────────

module "eks" {
  source = "../../components/eks"

  cluster_name                         = "${var.project}-app-${var.environment}"
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
  # Allow vault-cluster pods (same VPC) to reach this cluster's API on
  # 443 over the private endpoint — required for cross-cluster Vault
  # TokenReview from VSO. nonsensitive() is required because tfe_outputs
  # marks every value sensitive, and Terraform forbids sensitive values
  # in for_each (used by the EKS module's SG-rule loop).
  cluster_api_extra_ingress_cidrs = [nonsensitive(local.vpc_cidr_block)]
}

# ─── AWS Load Balancer Controller ─────────────────────────────────────────

module "alb_controller" {
  source = "../../components/alb-controller"

  cluster_name           = module.eks.cluster_name
  lb_controller_role_arn = module.eks.lb_controller_role_arn
  vpc_id                 = local.vpc_id
  aws_region             = var.aws_region
}

# ─── ExternalDNS (Route53 record automation) ──────────────────────────────

module "external_dns" {
  source = "../../components/external-dns"

  cluster_name          = module.eks.cluster_name
  domain                = var.base_domain
  zone_id               = local.zone_id
  external_dns_role_arn = module.eks.external_dns_role_arn
}

# ─── ArgoCD (GitOps continuous delivery) ──────────────────────────────────

module "argocd" {
  source = "../../components/argocd"

  gitops_repo_url        = "https://github.com/${var.github_org}/netlix-platform.git"
  gitops_target_revision = var.environment
  target_namespace       = "consul"
  environment            = var.environment
  domain                 = var.base_domain
  certificate_arn        = local.certificate_arn
}

# ─── Vault Configuration (PKI, auth, database engine, policies) ──────────

module "vault_config" {
  source = "../../components/vault-config"

  vault_address           = var.vault_address
  github_org              = var.github_org
  github_pat              = var.github_pat
  pki_allowed_domains     = [var.base_domain, "svc.cluster.local"]
  environment             = var.environment
  create_shared_resources = var.environment == "dev"
  tfc_organization_name   = var.tfc_organization
  admin_entity_id         = local.admin_entity_id
  dev_user                = var.dev_user
  dev_password            = var.dev_password

  # Cross-cluster Kubernetes auth — Vault calls THIS cluster's API for
  # TokenReview using the delegated reviewer SA from vault-token-reviewer.tf.
  kubernetes_host    = local.app_cluster_host
  kubernetes_ca_cert = local.app_cluster_ca
  token_reviewer_jwt = local.token_reviewer_jwt
}

# ─── Vault Secrets Operator (delivers secrets to app pods) ────────────────

module "vso" {
  source = "../../components/vso"

  vault_address        = local.vault_external_address
  vault_namespace      = module.vault_config.vault_namespace
  kubernetes_auth_path = module.vault_config.kubernetes_auth_path
  # ALB terminates TLS with publicly trusted ACM cert — no CA cert or skip needed
}

# ─── CloudWatch Monitoring (VPC Flow Logs + RDS + EKS Alarms) ────────────

module "monitoring" {
  source = "../../components/monitoring"

  environment            = var.environment
  project                = var.project
  vpc_flow_log_group_arn = local.flow_log_cloudwatch_log_group_arn
  eks_cluster_name       = module.eks.cluster_name
  alert_email            = var.alert_email
}

# ─── In-cluster Observability (Prometheus + Grafana + Loki) ───────────────

module "observability" {
  source = "../../components/observability"

  environment     = var.environment
  domain          = var.base_domain
  certificate_arn = local.certificate_arn
  vault_namespace = "vault"

  # VSO must be deployed first so the VaultStaticSecret CRD exists and the
  # default VaultConnection/VaultAuth is ready to sync the Grafana admin
  # secret. vault_config must exist so `secret/netlix/grafana` is populated.
  depends_on = [module.vso, module.vault_config]
}
