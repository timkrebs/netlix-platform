resource "vault_mount" "kv" {
  namespace   = vault_namespace.env.path_fq
  path        = "secret"
  type        = "kv-v2"
  description = "Netlix ${var.environment} application secrets"
}

resource "vault_kv_secret_v2" "app_config" {
  namespace = vault_namespace.env.path_fq
  mount     = vault_mount.kv.path
  name      = "netlix/config"

  data_json = jsonencode({
    app_name    = "netlix"
    environment = var.environment
    log_level   = "info"
    db_host     = var.rds_endpoint
    db_port     = tostring(var.rds_port)
    db_name     = var.db_name
  })
}
