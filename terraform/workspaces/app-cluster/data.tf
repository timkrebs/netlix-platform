# ─── Remote state from network workspace ──────────────────────────────────

data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "netlix-network-${var.environment}"
}

# ─── Remote state from vault-cluster workspace ────────────────────────────

data "tfe_outputs" "vault_cluster" {
  organization = var.tfc_organization
  workspace    = "netlix-vault-cluster-${var.environment}"
}

locals {
  # Network outputs
  vpc_id                            = data.tfe_outputs.network.values.vpc_id
  private_subnet_ids                = data.tfe_outputs.network.values.private_subnet_ids
  certificate_arn                   = data.tfe_outputs.network.values.certificate_arn
  zone_id                           = data.tfe_outputs.network.values.zone_id
  flow_log_cloudwatch_log_group_arn = data.tfe_outputs.network.values.flow_log_cloudwatch_log_group_arn

  # Vault cluster outputs
  vault_external_address = data.tfe_outputs.vault_cluster.values.vault_external_address
  vault_namespace        = data.tfe_outputs.vault_cluster.values.vault_namespace
  vault_ca_cert          = data.tfe_outputs.vault_cluster.values.vault_ca_cert
  # Identity entity ID used to grant the userpass admin access in this
  # environment's Vault namespace. Falls back to "" if vault-cluster
  # hasn't yet been re-applied with the entity resource.
  admin_entity_id = try(data.tfe_outputs.vault_cluster.values.admin_entity_id, "")
}
