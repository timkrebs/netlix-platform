output "cluster_endpoint" {
  description = "Vault EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Vault EKS cluster name"
  value       = module.eks.cluster_name
}

output "vault_external_address" {
  description = "Vault external address (public NLB endpoint)"
  value       = module.vault_server.vault_external_address
}

output "vault_internal_address" {
  description = "Vault internal address (in-cluster)"
  value       = module.vault_server.vault_internal_address
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = module.vault_server.vault_namespace
}

output "vault_ca_cert" {
  description = "Vault CA certificate secret name"
  value       = module.vault_server.vault_ca_cert
}

output "admin_entity_id" {
  description = "Vault identity entity ID for the userpass admin user — consumed by vault-config to grant per-namespace admin"
  value       = vault_identity_entity.admin.id
}

output "admin_username" {
  description = "Username of the userpass admin user"
  value       = var.username
}

# ─── Cross-cluster audit log shipping ─────────────────────────────────────
# Consumed by the app-cluster workspace via tfe_outputs (see
# workspaces/app-cluster/data.tf and main.tf observability module call).

output "loki_ingest_password" {
  description = "Basic auth password Promtail (vault cluster) uses to push to loki-gateway (app cluster). Read by app-cluster workspace via tfe_outputs."
  value       = random_password.loki_ingest.result
  sensitive   = true
}
