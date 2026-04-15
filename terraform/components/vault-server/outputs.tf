output "vault_internal_address" {
  description = "Vault internal address (for in-cluster access via VSO and apps)"
  value       = "https://vault-active.vault.svc.cluster.local:8200"
}

output "vault_external_address" {
  description = "Vault external address (NLB DNS — for TFC provider and external access)"
  value       = "https://${data.kubernetes_service.vault_lb.status[0].load_balancer[0].ingress[0].hostname}:8200"
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
