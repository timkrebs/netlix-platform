locals {
  vault_addr = var.vault_address
  env_ns     = "admin/${var.environment}"
}

# Per-environment child namespace under admin
resource "vault_namespace" "env" {
  path = var.environment
}
