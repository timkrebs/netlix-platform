variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

# ─── EKS ───────────────────────────────────────────────────────────────────

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
  description = "EC2 instance types for the App EKS node group"
  type        = list(string)
  # t3.medium = 2 vCPU / 4 GB — downsized from m6i.xlarge to reduce AWS
  # cost. NOTE: prior comment warned that smaller nodes caused Pending
  # pods under HPA peak; monitor scheduler/HPA after rollout and bump
  # back up (or scale node_desired_size) if pods queue.
  default = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  # Headroom for HPA peak: ~32 shop pods at peak + observability +
  # argocd + kube-system. With t3.medium (2 vCPU), 8 nodes = 16 vCPU.
  # Cluster Autoscaler isn't installed, so node count is static unless
  # Terraform bumps desired_size; max_size sets the ceiling if CA is
  # added later.
  default = 8

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

# ─── Vault ─────────────────────────────────────────────────────────────────

variable "vault_address" {
  description = "Vault external address (e.g. https://vault.dev.netlix.dev)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.vault_address))
    error_message = "vault_address must start with https://."
  }
}

variable "vault_root_token" {
  description = "Vault root token for provider authentication"
  type        = string
  sensitive   = true
}

# ─── Per-env Vault userpass user ─────────────────────────────────────────
# Created inside this env's Vault namespace by vault-config. Empty values
# skip user creation entirely (e.g. for staging if you don't want one).

variable "dev_user" {
  description = "Username for the per-env Vault userpass login (created inside this environment's namespace)."
  type        = string
  default     = ""
}

variable "dev_password" {
  description = "Password for the per-env Vault userpass login."
  type        = string
  sensitive   = true
  default     = ""
}

# ─── Application ───────────────────────────────────────────────────────────

variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = "timkrebs"
}

variable "github_pat" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "base_domain" {
  description = "Root domain managed by Route53 (e.g. netlix.dev)"
  type        = string
  default     = "netlix.dev"
}

# ─── Monitoring ────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

# ─── Metadata ──────────────────────────────────────────────────────────────

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
