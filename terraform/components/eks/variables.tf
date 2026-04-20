variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the node group"
  type        = list(string)
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public endpoint (empty = disabled)"
  type        = list(string)
  default     = []
}

variable "cluster_api_extra_ingress_cidrs" {
  description = "Additional CIDRs allowed to reach the cluster API (port 443) on the cluster security group. Use to allow other workloads in the same VPC (e.g. cross-cluster Vault TokenReview from vault-cluster). null = no extra rule."
  type        = list(string)
  default     = null
}

variable "additional_admin_arns" {
  description = "Additional IAM role/user ARNs to grant EKS cluster admin access"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}
