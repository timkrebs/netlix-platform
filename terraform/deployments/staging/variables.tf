variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "hcp_project_id" {
  description = "HCP project ID"
  type        = string
}

variable "hvn_id" {
  description = "HVN ID associated with the HCP Vault cluster"
  type        = string
}

variable "vault_cluster_id" {
  description = "HCP Vault cluster ID"
  type        = string
}

variable "vault_address" {
  description = "HCP Vault public address"
  type        = string
}

variable "vault_token" {
  description = "Vault admin token"
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "netlix-staging"
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "EKS node instance types"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 6
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.m6i.large"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "netlix"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.6"
}

variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = "timkrebs"
}

variable "github_pat" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
  default     = "placeholder"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "netlix"
}
