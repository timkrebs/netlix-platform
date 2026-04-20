variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must be a valid Kubernetes minor version (e.g. 1.31)."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types for the Vault EKS node group (small nodes)"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 5

  validation {
    condition     = var.node_max_size >= var.node_min_size
    error_message = "node_max_size must be greater than or equal to node_min_size."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public endpoint (empty = private-only)"
  type        = list(string)
  default     = []
}

variable "vault_ent_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}

variable "base_domain" {
  description = "Root domain managed by Route53 (e.g. netlix.dev)"
  type        = string
  default     = "netlix.dev"
}

variable "environment" {
  description = "Environment name (dev, staging)"
  type        = string

  validation {
    condition     = contains(["dev", "staging"], var.environment)
    error_message = "Environment must be dev or staging."
  }
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "netlix"
}

variable "tfc_organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "tim-krebs-org"
}

# ─── Vault provider auth (root namespace) ─────────────────────────────────

variable "vault_address" {
  description = "Vault external address (e.g. https://vault.dev.netlix.dev)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.vault_address))
    error_message = "vault_address must start with https://."
  }
}

variable "vault_root_token" {
  description = "Vault root token used to bootstrap the userpass auth method"
  type        = string
  sensitive   = true
}

# ─── Userpass admin user ──────────────────────────────────────────────────

variable "username" {
  description = "Username for the Vault userpass admin login"
  type        = string
}

variable "password" {
  description = "Password for the Vault userpass admin login"
  type        = string
  sensitive   = true
}

# ─── Userpass dev user (scoped to the dev namespace) ─────────────────────

variable "dev_user" {
  description = "Username for the Vault userpass dev login. Granted full access to the dev namespace only — no root or staging access."
  type        = string
}

variable "dev_password" {
  description = "Password for the Vault userpass dev login"
  type        = string
  sensitive   = true
}
