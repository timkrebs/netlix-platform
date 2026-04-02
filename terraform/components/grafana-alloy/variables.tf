variable "grafana_cloud_prometheus_url" {
  description = "Grafana Cloud Prometheus remote write endpoint"
  type        = string
}

variable "grafana_cloud_prometheus_username" {
  description = "Grafana Cloud Prometheus instance ID (numeric)"
  type        = string
}

variable "grafana_cloud_loki_url" {
  description = "Grafana Cloud Loki push endpoint"
  type        = string
}

variable "grafana_cloud_loki_username" {
  description = "Grafana Cloud Loki instance ID (numeric)"
  type        = string
}

variable "grafana_cloud_api_key" {
  description = "Grafana Cloud API key with MetricsPublisher and LogsPublisher roles"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "EKS cluster name for metric labels"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging)"
  type        = string
}
