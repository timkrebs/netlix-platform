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
      source = "hashicorp/aws"
      # Need v6.15+ for the aea201c fix
      # (hashicorp/terraform-provider-aws#44334): when an existing,
      # non-Auto-Mode EKS cluster transitions to having an explicit
      # `compute_config { enabled = false }` block, the provider must
      # populate storage_config + kubernetes_network_config in the
      # UpdateClusterConfig request or AWS returns "The type for cluster
      # update was not provided." Fix is v6.x only, not backported to
      # v5.x. v6 contract with v20.33.0 EKS module: module's
      # `required_providers { aws = ">= 5.83" }` has no upper bound, so
      # v6 is allowed.
      version = "~> 6.15"
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
