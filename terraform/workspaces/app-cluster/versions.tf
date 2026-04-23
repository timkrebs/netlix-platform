terraform {
  required_version = ">= 1.9"

  cloud {
    organization = "tim-krebs-org"

    workspaces {
      project = "netlix-platform"
      tags    = ["netlix", "app-cluster"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # Pin to 5.90.x — see vault-cluster/versions.tf for the full rationale.
      # Keeps AWS provider behavior consistent with the terraform-aws-modules/eks
      # v20.33.0 module; later 5.x releases enforce an EKS Auto Mode triad check
      # that's only resolved cleanly in EKS module v21.x (AWS provider v6.x).
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.0"
    }
  }
}
