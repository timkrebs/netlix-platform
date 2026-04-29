variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "domain" {
  description = "Base domain used to derive the Grafana hostname (grafana.<env>.<domain>)."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN attached to the Grafana ALB ingress."
  type        = string
}

variable "vault_namespace" {
  description = "Kubernetes namespace where Vault runs — used by the Vault ServiceMonitor selector."
  type        = string
  default     = "vault"
}

variable "apps_namespace" {
  description = "Kubernetes namespace where the shop services and Envoy sidecars run."
  type        = string
  default     = "consul"
}

variable "storage_class" {
  description = "StorageClass used for Prometheus / Grafana / Loki PVCs."
  type        = string
  default     = "gp3-encrypted"
}

variable "kube_prometheus_stack_version" {
  description = "prometheus-community/kube-prometheus-stack chart version."
  type        = string
  default     = "65.5.0"
}

variable "loki_version" {
  description = "grafana/loki chart version (single-binary mode)."
  type        = string
  default     = "6.16.0"
}

variable "promtail_version" {
  description = "grafana/promtail chart version."
  type        = string
  default     = "6.16.6"
}

variable "prometheus_retention" {
  description = "How long Prometheus retains data on disk."
  type        = string
  default     = "15d"
}

variable "loki_retention_period" {
  description = "How long Loki retains log chunks."
  type        = string
  default     = "168h"
}

variable "prometheus_storage_size" {
  description = "PVC size for Prometheus TSDB."
  type        = string
  default     = "50Gi"
}

variable "grafana_storage_size" {
  description = "PVC size for Grafana persistent data."
  type        = string
  default     = "10Gi"
}

variable "loki_storage_size" {
  description = "PVC size for Loki chunk + index storage (filesystem backend)."
  type        = string
  default     = "20Gi"
}

# ─── Loki cross-cluster ingest (vault-cluster Promtail → app-cluster Loki) ─

variable "loki_ingest_username" {
  description = "Basic auth username accepted by the loki-gateway for cross-cluster log ingest."
  type        = string
  default     = "vault-cluster"
}

variable "loki_ingest_password" {
  description = "Basic auth password accepted by the loki-gateway for cross-cluster log ingest. Must match the password configured for Promtail on the vault cluster (see vault-cluster workspace random_password.loki_ingest)."
  type        = string
  sensitive   = true

  # Refuse to apply with a blank password — that would silently expose the
  # public loki-ingest ingress with no auth. On a fresh bootstrap this
  # forces the correct apply order: vault-cluster must be applied first
  # so its random_password is generated, then app-cluster picks it up
  # via tfe_outputs.
  validation {
    condition     = length(var.loki_ingest_password) >= 16
    error_message = "loki_ingest_password must be at least 16 chars. On a fresh bootstrap, apply the vault-cluster workspace first — it generates the password and exposes it as an output that this workspace reads via tfe_outputs."
  }
}
