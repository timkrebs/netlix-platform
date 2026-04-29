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

# ─── Web shop bootstrap secrets ──────────────────────────────────────────
# Generated once per environment and surfaced to the cluster via VSO.
# Both shop services and the in-cluster Postgres StatefulSet read these
# from the same `shop-db` / `shop-jwt` k8s Secrets — single source of truth.

resource "random_password" "shop_jwt_signing_key" {
  length  = 64
  special = false
}

resource "random_password" "shop_db_password" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "shop_jwt" {
  namespace = vault_namespace.env.path_fq
  mount     = vault_mount.kv.path
  name      = "netlix/jwt"

  data_json = jsonencode({
    signing_key = random_password.shop_jwt_signing_key.result
  })
}

resource "vault_kv_secret_v2" "shop_db" {
  namespace = vault_namespace.env.path_fq
  mount     = vault_mount.kv.path
  name      = "netlix/db"

  data_json = jsonencode({
    username = "netlix"
    password = random_password.shop_db_password.result
  })
}

# ─── Web shop feature flags (KVv2 + VSO dynamic config demo) ─────────────
# Edited live during demos via `vault kv put` to flip UI behavior in the
# shop without redeploying. VSO syncs into Secret/shop-feature-flags,
# which the gateway pod mounts as a file at /etc/shop/flags.json. The
# gateway's /api/flags handler re-reads the file on demand and the React
# SPA polls it, so changes propagate without a pod restart.
#
# Single KVv2 key whose value is a JSON-encoded blob — VSO templating
# writes that blob verbatim to the projected file, and atomic file
# replacement avoids half-written reads.

resource "vault_kv_secret_v2" "shop_feature_flags" {
  namespace = vault_namespace.env.path_fq
  mount     = vault_mount.kv.path
  name      = "netlix/featureflags"

  data_json = jsonencode({
    "flags.json" = jsonencode({
      showPromoBanner = false
      promoText       = "FREE SHIPPING THIS WEEK"
    })
  })

  # Terraform owns the initial seed only — demo edits via `vault kv put`
  # must not be reverted by a future `terraform apply`.
  lifecycle {
    ignore_changes = [data_json]
  }
}

# ─── Grafana admin credentials ──────────────────────────────────────────
# Synced into the observability namespace by VSO (VaultStaticSecret in
# components/observability). Read by the kube-prometheus-stack chart's
# Grafana via grafana.admin.existingSecret.

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "grafana_admin" {
  namespace = vault_namespace.env.path_fq
  mount     = vault_mount.kv.path
  name      = "netlix/grafana"

  data_json = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })
}
