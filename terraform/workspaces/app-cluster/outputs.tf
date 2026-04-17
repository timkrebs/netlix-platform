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

output "argocd_url" {
  description = "ArgoCD dashboard URL"
  value       = "https://argocd.${var.environment}.${var.base_domain}"
}

output "app_url" {
  description = "Application URL"
  value       = "https://app.${var.environment}.${var.base_domain}"
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch monitoring dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${var.project}-${var.environment}"
}
