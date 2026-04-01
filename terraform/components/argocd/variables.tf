variable "gitops_repo_url" {
  description = "GitOps repository URL"
  type        = string
}

variable "target_namespace" {
  description = "Target Kubernetes namespace for the application"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging)"
  type        = string
}

variable "domain" {
  description = "Root domain (e.g. netlix.dev)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM wildcard certificate ARN for ALB TLS termination"
  type        = string
}
