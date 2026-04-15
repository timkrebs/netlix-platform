# ─── DNS ───────────────────────────────────────────────────────────────────

output "nameservers" {
  type        = list(string)
  description = "Route53 nameservers — update domain registrar with these"
  value       = component.dns.nameservers
}

output "certificate_arn" {
  type        = string
  description = "ACM wildcard certificate ARN"
  value       = component.dns.certificate_arn
}

# ─── Networking ────────────────────────────────────────────────────────────

output "vpc_id" {
  type  = string
  value = component.networking.vpc_id
}

# ─── EKS ───────────────────────────────────────────────────────────────────

output "cluster_endpoint" {
  type  = string
  value = component.eks.cluster_endpoint
}

output "cluster_name" {
  type  = string
  value = component.eks.cluster_name
}

# ─── RDS ───────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  type  = string
  value = component.rds.endpoint
}

# ─── Vault ─────────────────────────────────────────────────────────────────

output "vault_namespace" {
  type  = string
  value = component.vault_config.vault_namespace
}

output "vault_public_endpoint" {
  type  = string
  value = component.vault_server.vault_external_address
}

output "vault_internal_address" {
  type  = string
  value = component.vault_server.vault_internal_address
}
