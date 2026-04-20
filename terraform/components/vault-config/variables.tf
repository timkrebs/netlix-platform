variable "vault_address" {
  description = "Vault external address (NLB endpoint)"
  type        = string
}

variable "enable_database_engine" {
  description = "Enable Vault database secrets engine (requires RDS)"
  type        = bool
  default     = false
}

variable "rds_endpoint" {
  description = "RDS endpoint"
  type        = string
  default     = ""
}

variable "rds_port" {
  description = "RDS port"
  type        = number
  default     = 5432
}

variable "rds_admin_username" {
  description = "RDS admin username"
  type        = string
  default     = ""
}

variable "rds_admin_password" {
  description = "RDS admin password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = ""
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

variable "admin_entity_id" {
  description = "Vault identity entity ID of the userpass admin user (output from vault-cluster). When set, this user is granted full access to this environment's Vault namespace."
  type        = string
  default     = ""
}

# ─── Per-env userpass user ───────────────────────────────────────────────
# Mounts a userpass auth backend INSIDE this env's Vault namespace and
# creates this user with the namespace-admin policy. Login goes directly
# to the env namespace — no group plumbing needed.
# Both vars must be non-empty for the resources to be created.

variable "dev_user" {
  description = "Username for the per-env userpass login (created inside this Vault namespace)."
  type        = string
  default     = ""
}

variable "dev_password" {
  description = "Password for the per-env userpass login."
  type        = string
  sensitive   = true
  default     = ""
}
