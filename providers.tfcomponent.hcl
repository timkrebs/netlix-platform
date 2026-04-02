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
  hcp = {
    source  = "hashicorp/hcp"
    version = "~> 0.100"
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
  grafana = {
    source  = "grafana/grafana"
    version = "~> 3.0"
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

# ─── HCP Provider ─────────────────────────────────────────────────────────

provider "hcp" "main" {
  config {
    project_id    = var.hcp_project_id
    client_id     = var.hcp_client_id
    client_secret = var.hcp_client_secret
  }
}

# ─── Vault Provider ───────────────────────────────────────────────────────

provider "vault" "hcp" {
  config {
    address   = var.vault_address
    namespace = "admin"

    auth_login_jwt {
      mount = "jwt-tfc"
      role  = "tfc-stacks"
      jwt   = var.vault_identity_token
    }
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

# ─── Grafana Cloud Provider ──────────────────────────────────────────────

provider "grafana" "cloud" {
  config {
    url  = var.grafana_cloud_stack_url
    auth = var.grafana_cloud_api_key
  }
}
