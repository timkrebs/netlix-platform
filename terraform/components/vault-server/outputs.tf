output "vault_internal_address" {
  description = "Vault internal address (for in-cluster access via VSO and apps)"
  value       = "https://vault-active.vault.svc.cluster.local:8200"
}

output "vault_external_address" {
  description = "Vault external address (public domain — ALB with ACM cert)"
  value       = "https://vault.${var.environment}.${var.domain}"
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = local.vault_namespace
}

output "vault_ca_cert" {
  description = "Vault CA certificate secret name (in vault namespace)"
  value       = "vault-ca"
}

output "vault_kms_irsa_role_arn" {
  description = "IRSA role ARN for Vault KMS access"
  value       = module.vault_kms_irsa.iam_role_arn
}
