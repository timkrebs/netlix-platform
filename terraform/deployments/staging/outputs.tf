output "vpc_id" {
  value = module.networking.vpc_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "vault_public_endpoint" {
  value = module.vault_config.vault_public_endpoint
}

output "hvn_peering_id" {
  value = module.hvn_peering.peering_id
}
