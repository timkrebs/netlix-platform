resource "vault_mount" "kv" {
  path        = "secret/${var.environment}"
  type        = "kv-v2"
  description = "Netlix ${var.environment} application secrets"
}

resource "vault_kv_secret_v2" "app_config" {
  mount = vault_mount.kv.path
  name  = "netlix/config"

  data_json = jsonencode({
    app_name    = "netlix"
    environment = var.environment
    log_level   = "info"
    db_host     = var.rds_endpoint
    db_port     = tostring(var.rds_port)
    db_name     = var.db_name
  })
}
