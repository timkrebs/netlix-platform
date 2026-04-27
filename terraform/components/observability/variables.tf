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
