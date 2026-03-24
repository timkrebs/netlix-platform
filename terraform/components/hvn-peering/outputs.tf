output "hvn_cidr_block" {
  description = "HVN CIDR block for security group rules"
  value       = data.hcp_hvn.vault.cidr_block
}

output "peering_id" {
  description = "AWS VPC peering connection ID"
  value       = hcp_aws_network_peering.vault_to_vpc.provider_peering_id
}
