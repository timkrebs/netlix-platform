output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_ca_certificate" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}
output "cluster_token" {
  value     = data.aws_eks_cluster_auth.this.token
  sensitive = true
}
output "cluster_name" { value = module.eks.cluster_name }
output "cluster_security_group_id" { value = module.eks.cluster_security_group_id }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "oidc_provider_url" { value = module.eks.cluster_oidc_issuer_url }
output "lb_controller_role_arn" { value = module.lb_controller_irsa.iam_role_arn }
