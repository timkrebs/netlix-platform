variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must be a valid Kubernetes minor version (e.g. 1.31)."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types for the Vault EKS node group (small nodes)"
  type        = list(string)
  # t3.small = 2 vCPU / 2 GB — downsized from t3.medium to reduce AWS
  # cost. Vault server pods are lightweight; revisit if memory pressure
  # appears on the Vault statefulset.
  default = ["t3.small"]
}

variable "node_desired_size" {
  description = "Desired number of nodes. 4 (was 3) — t3.small caps at 11 pods/node, and a 3-node cluster runs out of slots once you stack 5 Vault replicas + cert-manager + ALB controller + external-dns + ebs-csi + coredns + aws-node + kube-proxy + Promtail DaemonSet (1 per node). NOTE: the EKS module pins ignore_changes on scaling_config.desired_size (so cluster-autoscaler can manage it), so a Terraform-only bump here does NOT scale the cluster. To go from 3→4 nodes, either run `aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name <ng> --scaling-config minSize=3,maxSize=6,desiredSize=4` first, or set this on initial create."
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "Minimum number of nodes. Kept at 3 (not aligned with desired_size=4) because AWS rejects updating min above the current desired_size, and the EKS module's ignore_changes on desired_size prevents Terraform from coordinating the two updates in a single apply."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 6
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public endpoint (empty = private-only)"
  type        = list(string)
  default     = []
}

variable "vault_ent_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}

variable "base_domain" {
  description = "Root domain managed by Route53 (e.g. netlix.dev)"
  type        = string
  default     = "netlix.dev"
}

variable "environment" {
  description = "Environment name (dev, staging)"
  type        = string

  validation {
    condition     = contains(["dev", "staging"], var.environment)
    error_message = "Environment must be dev or staging."
  }
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "netlix"
}

variable "tfc_organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "tim-krebs-org"
}

# ─── Vault provider auth (root namespace) ─────────────────────────────────

variable "vault_address" {
  description = "Vault external address (e.g. https://vault.dev.netlix.dev)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.vault_address))
    error_message = "vault_address must start with https://."
  }
}

variable "vault_root_token" {
  description = "Vault root token used to bootstrap the userpass auth method"
  type        = string
  sensitive   = true
}

# ─── Userpass admin user ──────────────────────────────────────────────────

variable "username" {
  description = "Username for the Vault userpass admin login"
  type        = string
}

variable "password" {
  description = "Password for the Vault userpass admin login"
  type        = string
  sensitive   = true
}

