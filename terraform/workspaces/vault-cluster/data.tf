# ─── Remote state from network workspace ──────────────────────────────────

data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "netlix-network-${var.environment}"
}

locals {
  vpc_id             = data.tfe_outputs.network.values.vpc_id
  private_subnet_ids = data.tfe_outputs.network.values.private_subnet_ids
  certificate_arn    = data.tfe_outputs.network.values.certificate_arn
  zone_id            = data.tfe_outputs.network.values.zone_id
}
