variable "environment" {
  description = "Deployment environment (dev, staging)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name for dashboard filtering"
  type        = string
}

variable "prometheus_datasource_uid" {
  description = "UID of the Grafana Cloud Prometheus data source (usually 'grafanacloud-prom')"
  type        = string
  default     = "grafanacloud-prom"
}

variable "loki_datasource_uid" {
  description = "UID of the Grafana Cloud Loki data source (usually 'grafanacloud-logs')"
  type        = string
  default     = "grafanacloud-logs"
}
