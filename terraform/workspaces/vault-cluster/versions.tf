terraform {
  required_version = ">= 1.9"

  cloud {
    organization = "tim-krebs-org"

    workspaces {
      project = "netlix-platform"
      tags    = ["netlix", "vault-cluster"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # Pin to 5.90.x — 5.91+ tightened the EKS Auto Mode
      # validateAutoModeCustsomizeDiff such that the terraform-aws-modules/eks
      # v20.33.0 module (which doesn't emit compute_config / elastic_load_balancing /
      # storage_config.block_storage consistently) trips the triad check. The
      # proper upstream fix is in EKS module v21.3.2+, which forces AWS provider
      # v6.x and breaks IRSA/OIDC — out of scope for a hotfix. Bump this when
      # we upgrade the EKS module.
      version = "~> 5.90.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.62"
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
}
