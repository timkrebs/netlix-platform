variable "vault_address" {
  description = "Vault external address (NLB endpoint)"
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
  ephemeral   = true
}

variable "pki_allowed_domains" {
  description = "Allowed domains for PKI certificates"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tfc_organization_name" {
  description = "HCP Terraform organization name for JWT auth bound_claims"
  type        = string
  default     = ""
}

variable "create_shared_resources" {
  description = "Create shared Vault resources (userpass, root PKI, admin policy). Set to true for only one environment."
  type        = bool
  default     = false
}
