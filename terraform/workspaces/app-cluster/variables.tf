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
}

variable "node_instance_types" {
  description = "EC2 instance types for the App EKS node group"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 5
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public endpoint (empty = disabled)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ─── Vault ─────────────────────────────────────────────────────────────────

variable "vault_address" {
  description = "Vault external address (e.g. https://vault.dev.netlix.dev:8200)"
  type        = string
}

variable "vault_root_token" {
  description = "Vault root token for provider authentication"
  type        = string
  sensitive   = true
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
