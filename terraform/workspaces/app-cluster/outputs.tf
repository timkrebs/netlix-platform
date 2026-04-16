output "cluster_endpoint" {
  description = "App EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "App EKS cluster name"
  value       = module.eks.cluster_name
}

output "vault_namespace" {
  description = "Vault namespace for this environment"
  value       = module.vault_config.vault_namespace
}

output "vault_public_endpoint" {
  description = "Vault public endpoint"
  value       = module.vault_config.vault_public_endpoint
}
