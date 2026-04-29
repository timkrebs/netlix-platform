variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging)"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vault_ent_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL for IRSA"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cert_manager_namespace" {
  description = "cert-manager namespace (dependency anchor — ensures cert-manager is deployed before Vault)"
  type        = string
}

variable "domain" {
  description = "Base domain for public DNS (e.g., netlix.dev)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM wildcard certificate ARN for the ALB"
  type        = string
}

variable "vault_helm_version" {
  description = "Vault Helm chart version"
  type        = string
  default     = "0.29.1"
}

variable "vault_image_tag" {
  description = "Vault Enterprise container image tag"
  type        = string
  default     = "1.18.4-ent"
}

variable "vault_replicas" {
  description = "Number of Vault server replicas (should be odd for Raft consensus)"
  type        = number
  default     = 5
}

variable "storage_class" {
  description = "Kubernetes StorageClass for Vault data and audit volumes. Use gp3-encrypted for new deployments."
  type        = string
  default     = "gp2"
}

# ─── Promtail (Vault audit log shipper → app-cluster Loki) ────────────────

variable "promtail_chart_version" {
  description = "grafana/promtail chart version. Pinned to match the version on the app cluster for label/parsing parity."
  type        = string
  default     = "6.16.6"
}

variable "loki_ingest_endpoint" {
  description = "URL where Promtail pushes log batches. Points at the app-cluster's loki-gateway ALB ingress."
  type        = string
}

variable "loki_ingest_username" {
  description = "Basic auth username for the loki-gateway ingest endpoint."
  type        = string
  default     = "vault-cluster"
}

variable "loki_ingest_password" {
  description = "Basic auth password matching the secret in app-cluster's observability namespace."
  type        = string
  sensitive   = true
}
