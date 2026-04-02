variable "cluster_name" {
  type        = string
  description = "EKS cluster name for Datadog agent tagging"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging)"
}

variable "datadog_site" {
  type        = string
  default     = "datadoghq.eu"
  description = "Datadog site (e.g. datadoghq.eu, datadoghq.com)"
}
