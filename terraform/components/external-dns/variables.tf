variable "cluster_name" {
  description = "EKS cluster name (used as TXT record owner ID)"
  type        = string
}

variable "domain" {
  description = "Domain to filter (e.g. netlix.dev)"
  type        = string
}

variable "external_dns_role_arn" {
  description = "IAM role ARN for the ExternalDNS service account (IRSA)"
  type        = string
}
