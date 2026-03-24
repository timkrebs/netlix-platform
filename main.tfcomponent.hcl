# ─── Required providers ────────────────────────────────────────────────────

required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
  vault = {
    source  = "hashicorp/vault"
    version = "~> 4.0"
  }
  helm = {
    source  = "hashicorp/helm"
    version = "~> 2.0"
  }
  kubernetes = {
    source  = "hashicorp/kubernetes"
    version = "~> 2.0"
  }
  random = {
    source  = "hashicorp/random"
    version = "~> 3.0"
  }
  time = {
    source  = "hashicorp/time"
    version = "~> 0.12"
  }
  tls = {
    source  = "hashicorp/tls"
    version = "~> 4.0"
  }
  null = {
    source  = "hashicorp/null"
    version = "~> 3.0"
  }
  cloudinit = {
    source  = "hashicorp/cloudinit"
    version = "~> 2.0"
  }
}

# ─── Variables ─────────────────────────────────────────────────────────────

variable "aws_identity_token" {
  type      = string
  ephemeral = true
}
variable "aws_region"           { type = string }
variable "role_arn"             { type = string }
variable "hcp_project_id"       { type = string }
variable "vault_cluster_id"     { type = string }
variable "vault_address"        { type = string }
variable "vpc_cidr"             { type = string }
variable "azs"                  { type = list(string) }
variable "cluster_name"         { type = string }
variable "cluster_version"      { type = string }
variable "node_instance_types"  { type = list(string) }
variable "node_desired_size"    { type = number }
variable "node_min_size"        { type = number }
variable "node_max_size"        { type = number }
variable "db_instance_class"    { type = string }
variable "db_name"              { type = string }
variable "db_engine_version"    { type = string }
variable "github_org"           { type = string }

variable "github_pat" {
  type      = string
  sensitive = true
}

variable "environment"          { type = string }
variable "project"              { type = string }
variable "default_tags"         { type = map(string) }

# ─── Providers ─────────────────────────────────────────────────────────────

provider "aws" "main" {
  config {
    region = var.aws_region

    assume_role_with_web_identity {
      role_arn           = var.role_arn
      web_identity_token = var.aws_identity_token
    }

    default_tags {
      tags = merge(var.default_tags, {
        environment = var.environment
        project     = var.project
      })
    }
  }
}

provider "vault" "hcp" {
  config {
    address   = var.vault_address
    namespace = "admin"
  }
}

provider "helm" "eks" {
  config {
    kubernetes {
      host                   = component.eks.cluster_endpoint
      cluster_ca_certificate = base64decode(component.eks.cluster_ca_certificate)
      token                  = component.eks.cluster_token
    }
  }
}

provider "kubernetes" "eks" {
  config {
    host                   = component.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(component.eks.cluster_ca_certificate)
    token                  = component.eks.cluster_token
  }
}

provider "random" "default" {
  config {}
}

provider "time" "default" {
  config {}
}

provider "tls" "default" {
  config {}
}

provider "null" "default" {
  config {}
}

provider "cloudinit" "default" {
  config {}
}

# ─── Components ────────────────────────────────────────────────────────────

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
    environment         = var.environment
    project             = var.project
  }

  providers = {
    aws       = provider.aws.main
    time      = provider.time.default
    tls       = provider.tls.default
    null      = provider.null.default
    cloudinit = provider.cloudinit.default
  }
}

component "rds" {
  source = "./terraform/components/rds"

  inputs = {
    vpc_id              = component.networking.vpc_id
    private_subnet_ids  = component.networking.private_subnet_ids
    db_instance_class   = var.db_instance_class
    db_name             = var.db_name
    db_engine_version   = var.db_engine_version
    eks_security_group  = component.eks.cluster_security_group_id
    environment         = var.environment
    project             = var.project
  }

  providers = {
    aws    = provider.aws.main
    random = provider.random.default
  }
}

component "vault_config" {
  source = "./terraform/components/vault-config"

  inputs = {
    vault_cluster_id      = var.vault_cluster_id
    vault_address         = var.vault_address
    eks_cluster_endpoint  = component.eks.cluster_endpoint
    eks_cluster_ca        = component.eks.cluster_ca_certificate
    eks_oidc_provider_arn = component.eks.oidc_provider_arn
    eks_oidc_provider_url = component.eks.oidc_provider_url
    rds_endpoint          = component.rds.endpoint
    rds_port              = component.rds.port
    rds_admin_username    = component.rds.admin_username
    rds_admin_password    = component.rds.admin_password
    db_name               = var.db_name
    github_org            = var.github_org
    github_pat            = var.github_pat
    pki_allowed_domains   = ["netlix.dev", "netlix.internal", "svc.cluster.local"]
    environment           = var.environment
  }

  providers = {
    vault = provider.vault.hcp
  }
}

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

component "argocd" {
  source = "./terraform/components/argocd"

  inputs = {
    gitops_repo_url  = "https://github.com/${var.github_org}/netlix-gitops.git"
    target_namespace = "netlix"
  }

  providers = {
    helm       = provider.helm.eks
    kubernetes = provider.kubernetes.eks
  }
}
