variable "vault_cluster_id" {
  description = "HCP Vault cluster ID"
  type        = string
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  type        = string
}

variable "eks_cluster_ca" {
  description = "EKS cluster CA certificate (base64)"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL"
  type        = string
}

variable "rds_endpoint" {
  description = "RDS endpoint"
  type        = string
}

variable "rds_port" {
  description = "RDS port"
  type        = number
}

variable "rds_admin_username" {
  description = "RDS admin username"
  type        = string
}

variable "rds_admin_password" {
  description = "RDS admin password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "github_org" {
  description = "GitHub organization"
  type        = string
}

variable "github_pat" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "pki_allowed_domains" {
  description = "Allowed domains for PKI certificates"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}
