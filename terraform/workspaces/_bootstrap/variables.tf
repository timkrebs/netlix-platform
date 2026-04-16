variable "tfc_organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "tim-krebs-org"
}

variable "tfc_project_name" {
  description = "HCP Terraform project name"
  type        = string
  default     = "netlix-platform"
}

variable "enable_vcs" {
  description = "Enable VCS integration for workspaces and Sentinel policy set. Set to false to create workspaces without VCS (configure manually later)."
  type        = bool
  default     = false
}

variable "github_oauth_token_id" {
  description = "GitHub OAuth token ID configured in HCP Terraform (required when enable_vcs = true)"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository identifier (org/repo)"
  type        = string
  default     = "timkrebs/netlix-platform"
}

variable "vcs_branch" {
  description = "VCS branch to trigger runs"
  type        = string
  default     = "dev"
}

variable "aws_account_id" {
  description = "AWS account ID for dynamic provider credentials"
  type        = string
  default     = "173003892479"
}

variable "environments" {
  description = "Environments to create workspaces for"
  type = map(object({
    vcs_branch = string
    role_arn   = string
  }))
  default = {
    dev = {
      vcs_branch = "dev"
      role_arn   = "arn:aws:iam::173003892479:role/tfc-netlix-dev"
    }
  }
}

variable "vault_varset_id" {
  description = "ID of the existing netlix-vault variable set"
  type        = string
  default     = "varset-KzPCKUxZHwNvVQ4Z"
}
