# ─── DNS (Route53 + ACM) ───────────────────────────────────────────────────

component "dns" {
  source = "./terraform/components/dns"

  inputs = {
    domain      = var.base_domain
    cluster_env = var.environment
  }

  providers = {
    aws = provider.aws.main
  }
}

# ─── Networking (VPC + subnets + flow logs) ────────────────────────────────

component "networking" {
  source = "./terraform/components/networking"

  inputs = {
    vpc_cidr    = var.vpc_cidr
    azs         = var.azs
    environment = var.environment
    project     = var.project
  }

  providers = {
    aws = provider.aws.main
  }
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────

component "eks" {
  source = "./terraform/components/eks"

  inputs = {
    cluster_name        = var.cluster_name
    cluster_version     = var.cluster_version
    vpc_id              = component.networking.vpc_id
    private_subnet_ids  = component.networking.private_subnet_ids
    node_instance_types = var.node_instance_types
    node_desired_size   = var.node_desired_size
    node_min_size       = var.node_min_size
    node_max_size       = var.node_max_size
    environment                          = var.environment
    project                              = var.project
    cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  }

  providers = {
    aws       = provider.aws.main
    time      = provider.time.default
    tls       = provider.tls.default
    null      = provider.null.default
    cloudinit = provider.cloudinit.default
  }
}

# ─── HVN Peering (HCP Vault ↔ AWS VPC) ────────────────────────────────────

component "hvn_peering" {
  source = "./terraform/components/hvn-peering"

  inputs = {
    hvn_id                  = var.hvn_id
    peer_vpc_id             = component.networking.vpc_id
    peer_account_id         = component.networking.vpc_owner_id
    peer_vpc_region         = var.aws_region
    vpc_cidr                = var.vpc_cidr
    private_route_table_ids = component.networking.private_route_table_ids
    environment             = var.environment
    project                 = var.project
  }

  providers = {
    hcp = provider.hcp.main
    aws = provider.aws.main
  }
}

# ─── RDS PostgreSQL ───────────────────────────────────────────────────────

component "rds" {
  source = "./terraform/components/rds"

  inputs = {
    vpc_id             = component.networking.vpc_id
    private_subnet_ids = component.networking.private_subnet_ids
    db_instance_class  = var.db_instance_class
    db_name            = var.db_name
    db_engine_version  = var.db_engine_version
    eks_security_group = component.eks.cluster_security_group_id
    hvn_cidr_block     = component.hvn_peering.hvn_cidr_block
    environment        = var.environment
    project            = var.project
  }

  providers = {
    aws    = provider.aws.main
    random = provider.random.default
  }
}

# ─── Vault Configuration ──────────────────────────────────────────────────

component "vault_config" {
  source = "./terraform/components/vault-config"

  inputs = {
    vault_cluster_id        = var.vault_cluster_id
    vault_address           = var.vault_address
    eks_cluster_endpoint    = component.eks.cluster_endpoint
    eks_cluster_ca          = component.eks.cluster_ca_certificate
    eks_oidc_provider_arn   = component.eks.oidc_provider_arn
    eks_oidc_provider_url   = component.eks.oidc_provider_url
    rds_endpoint            = component.rds.endpoint
    rds_port                = component.rds.port
    rds_admin_username      = component.rds.admin_username
    rds_admin_password      = component.rds.admin_password
    db_name                 = var.db_name
    github_org              = var.github_org
    github_pat              = var.github_pat
    pki_allowed_domains     = [var.base_domain, "${var.base_domain}", "svc.cluster.local"]
    environment             = var.environment
    create_shared_resources = var.environment == "dev"
    tfc_organization_name   = var.tfc_organization_name
  }

  providers = {
    vault      = provider.vault.hcp
    kubernetes = provider.kubernetes.eks
  }
}

# ─── Vault Secrets Operator ───────────────────────────────────────────────

component "vso" {
  source = "./terraform/components/vso"

  inputs = {
    vault_address        = component.vault_config.vault_public_endpoint
    vault_namespace      = component.vault_config.vault_namespace
    kubernetes_auth_path = component.vault_config.kubernetes_auth_path
  }

  providers = {
    helm       = provider.helm.eks
    kubernetes = provider.kubernetes.eks
  }
}

# ─── AWS Load Balancer Controller ─────────────────────────────────────────

component "alb_controller" {
  source = "./terraform/components/alb-controller"

  inputs = {
    cluster_name           = component.eks.cluster_name
    lb_controller_role_arn = component.eks.lb_controller_role_arn
    vpc_id                 = component.networking.vpc_id
    aws_region             = var.aws_region
  }

  providers = {
    helm = provider.helm.eks
  }
}

# ─── ExternalDNS (Route53 record automation) ──────────────────────────────

component "external_dns" {
  source = "./terraform/components/external-dns"

  inputs = {
    cluster_name          = component.eks.cluster_name
    domain                = var.base_domain
    zone_id               = var.route53_zone_id
    external_dns_role_arn = component.eks.external_dns_role_arn
  }

  providers = {
    helm = provider.helm.eks
  }
}

# ─── ArgoCD ───────────────────────────────────────────────────────────────

component "argocd" {
  source = "./terraform/components/argocd"

  inputs = {
    gitops_repo_url        = "https://github.com/${var.github_org}/netlix-platform.git"
    gitops_target_revision = var.environment
    target_namespace       = "consul"
    environment            = var.environment
    domain                 = var.base_domain
    certificate_arn        = component.dns.certificate_arn
  }

  providers = {
    helm = provider.helm.eks
  }
}

# ─── Grafana removal (destroy Helm releases) ─────────────────────────────
# These removed blocks tell Stacks to destroy the deployed resources.
# Delete these blocks + the grafana provider + component directories
# after the next successful Stack apply.

removed {
  from   = component.grafana_k8s_monitoring
  source = "./terraform/components/grafana-k8s-monitoring"

  providers = {
    helm       = provider.helm.eks
    kubernetes = provider.kubernetes.eks
  }
}

removed {
  from   = component.grafana_alloy
  source = "./terraform/components/grafana-alloy"

  providers = {
    helm = provider.helm.eks
  }
}

# ─── CloudWatch Monitoring (VPC Flow Logs + RDS + EKS Alarms) ────────────

component "monitoring" {
  source = "./terraform/components/monitoring"

  inputs = {
    environment             = var.environment
    project                 = var.project
    vpc_flow_log_group_arn = component.networking.flow_log_cloudwatch_log_group_arn
    rds_instance_id         = component.rds.instance_id
    eks_cluster_name        = var.cluster_name
    alert_email             = var.alert_email
  }

  providers = {
    aws = provider.aws.main
  }
}

removed {
  from   = component.grafana_dashboards
  source = "./terraform/components/grafana-dashboards"

  providers = {
    grafana = provider.grafana.cloud
  }
}
