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

variable "zone_id" {
  description = "Route53 hosted zone ID to manage records in"
  type        = string
}
