variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the monitoring stack"
  type        = string
  default     = "grafana-system"
}

# ─── Grafana Cloud Destinations ───────────────────────────────────────────

variable "prometheus_url" {
  description = "Grafana Cloud Prometheus remote write URL"
  type        = string
}

variable "prometheus_username" {
  description = "Grafana Cloud Prometheus instance ID"
  type        = string
}

variable "loki_url" {
  description = "Grafana Cloud Loki push URL"
  type        = string
}

variable "loki_username" {
  description = "Grafana Cloud Loki instance ID"
  type        = string
}

variable "otlp_url" {
  description = "Grafana Cloud OTLP gateway URL"
  type        = string
}

variable "otlp_username" {
  description = "Grafana Cloud OTLP instance ID"
  type        = string
}

variable "pyroscope_url" {
  description = "Grafana Cloud Pyroscope URL"
  type        = string
}

variable "pyroscope_username" {
  description = "Grafana Cloud Pyroscope instance ID"
  type        = string
}

