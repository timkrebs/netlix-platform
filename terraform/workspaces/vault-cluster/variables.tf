variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
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
