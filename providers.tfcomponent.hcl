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
  hcp = {
    source  = "hashicorp/hcp"
    version = "~> 0.100"
  }
}

# ─── AWS Provider (OIDC workload identity — no static credentials) ─────────

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
        managed_by  = "terraform"
      })
    }
  }
}

# ─── Vault Provider (token auth to self-hosted Vault Enterprise on EKS) ───

provider "vault" "main" {
  config {
    address          = component.vault_server.vault_external_address
    token            = var.vault_root_token
    skip_child_token = true
  }
}

# ─── Kubernetes & Helm Providers (wired to EKS component output) ──────────

provider "kubernetes" "eks" {
  config {
    host                   = component.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(component.eks.cluster_ca_certificate)
    token                  = component.eks.cluster_token
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

# ─── HCP Provider (required only for the hvn_peering removed block) ─────────

provider "hcp" "default" {
  config {}
}

# ─── Utility Providers ────────────────────────────────────────────────────

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
