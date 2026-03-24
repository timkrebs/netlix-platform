# Look up the existing HVN associated with the Vault cluster
data "hcp_hvn" "vault" {
  hvn_id = var.hvn_id
}

# Create the HCP-side peering request
resource "hcp_aws_network_peering" "vault_to_vpc" {
  hvn_id          = data.hcp_hvn.vault.hvn_id
  peering_id      = "${var.project}-${var.environment}"
  peer_vpc_id     = var.peer_vpc_id
  peer_account_id = var.peer_account_id
  peer_vpc_region = var.peer_vpc_region
}

# Accept the peering on the AWS side
resource "aws_vpc_peering_connection_accepter" "vault" {
  vpc_peering_connection_id = hcp_aws_network_peering.vault_to_vpc.provider_peering_id
  auto_accept               = true

  tags = {
    Name = "${var.project}-${var.environment}-hvn-peering"
    Side = "Accepter"
  }
}

# Create an HVN route so HCP can reach the AWS VPC CIDR
resource "hcp_hvn_route" "to_vpc" {
  hvn_link         = data.hcp_hvn.vault.self_link
  hvn_route_id     = "${var.project}-${var.environment}-route"
  destination_cidr = var.vpc_cidr
  target_link      = hcp_aws_network_peering.vault_to_vpc.self_link
}

# Add routes on the AWS side so private subnets can reach the HVN CIDR
resource "aws_route" "private_to_hvn" {
  count                     = length(var.private_route_table_ids)
  route_table_id            = var.private_route_table_ids[count.index]
  destination_cidr_block    = data.hcp_hvn.vault.cidr_block
  vpc_peering_connection_id = hcp_aws_network_peering.vault_to_vpc.provider_peering_id
}
