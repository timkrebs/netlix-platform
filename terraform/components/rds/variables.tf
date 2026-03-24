variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
}

variable "eks_security_group" {
  description = "EKS cluster security group ID"
  type        = string
}

variable "hvn_cidr_block" {
  description = "HVN CIDR block for Vault access to RDS"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}
