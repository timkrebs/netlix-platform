variable "cluster_name" {
  description = "EKS cluster name for metric labels"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging)"
  type        = string
}
