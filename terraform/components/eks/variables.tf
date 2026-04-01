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

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "route53_zone_arns" {
  description = "Route53 hosted zone ARNs that ExternalDNS is allowed to manage"
  type        = list(string)
  default     = []
}
