# ─── Identity & Authentication ─────────────────────────────────────────────

variable "aws_identity_token" {
  type      = string
  ephemeral = true
}

variable "aws_region" {
  type = string
}

variable "role_arn" {
  type = string
}

variable "hcp_project_id" {
  type = string
}

variable "hcp_client_id" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "hcp_client_secret" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "vault_cluster_id" {
  type = string
}

variable "vault_address" {
  type = string
}

variable "vault_identity_token" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "hvn_id" {
  type = string
}

# ─── Networking ────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

# ─── DNS ───────────────────────────────────────────────────────────────────

variable "base_domain" {
  type        = string
  description = "Root domain managed by Route53 (e.g. netlix.dev)"
}

variable "route53_zone_id" {
  type        = string
  description = "Pre-existing Route53 hosted zone ID (the one the registrar delegates to)"
}

# ─── EKS ───────────────────────────────────────────────────────────────────

variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach EKS API. Empty list disables public access."
  default     = []
}

# ─── RDS ───────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_engine_version" {
  type = string
}

# ─── Application ───────────────────────────────────────────────────────────

variable "github_org" {
  type = string
}

variable "github_pat" {
  type      = string
  sensitive = true
}

# ─── Grafana Cloud ────────────────────────────────────────────────────────

variable "grafana_cloud_prometheus_url" {
  type        = string
  description = "Grafana Cloud Prometheus remote write endpoint"
  default     = ""
}

variable "grafana_cloud_prometheus_username" {
  type        = string
  description = "Grafana Cloud Prometheus instance ID"
  default     = ""
}

variable "grafana_cloud_loki_url" {
  type        = string
  description = "Grafana Cloud Loki push endpoint"
  default     = ""
}

variable "grafana_cloud_loki_username" {
  type        = string
  description = "Grafana Cloud Loki instance ID"
  default     = ""
}

variable "grafana_cloud_api_key" {
  type        = string
  description = "Grafana Cloud API key"
  sensitive   = true
}

variable "grafana_cloud_stack_url" {
  type        = string
  description = "Grafana Cloud stack URL (e.g. https://yourstack.grafana.net)"
  default     = ""
}

# ─── Monitoring ───────────────────────────────────────────────────────────

variable "alert_email" {
  type        = string
  description = "Email for CloudWatch alarm notifications"
  default     = ""
}

# ─── Metadata ──────────────────────────────────────────────────────────────

variable "environment" {
  type = string
}

variable "tfc_organization_name" {
  type        = string
  description = "HCP Terraform organization name (for Vault JWT auth bound_claims)"
}

variable "project" {
  type = string
}

variable "default_tags" {
  type    = map(string)
  default = {}
}
