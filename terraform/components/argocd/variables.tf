variable "gitops_repo_url" {
  description = "GitOps repository URL"
  type        = string
}

variable "target_namespace" {
  description = "Target Kubernetes namespace for the application"
  type        = string
}
