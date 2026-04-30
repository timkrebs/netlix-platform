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

  # Phase 6.2 multi-key format for hot rotation. The whole `keys` field
  # is a single JSON-encoded string so VSO templates it verbatim into
  # the K8s Secret's `keys.json` data key — see
  # app/manifests/shop/vault-secrets.yaml's shop-jwt VaultStaticSecret.
  # The auth + orders services mount that file and hot-reload it via
  # JWKSManager (app/services/{auth,orders}/jwks.go).
  #
  # Rotation procedure:
  #   1. Edit the keys map below: add a new entry (e.g. v2), change
  #      primary_kid to the new entry. Keep the previous entry (v1)
  #      so old tokens still verify until they expire.
  #   2. `terraform apply`. Within ~60 s VSO + kubelet propagate the
  #      new file; auth starts signing with the new primary key, orders
  #      verifies tokens against both the new and previous keys.
  #   3. Once all old-primary tokens have expired (ACCESS_TOKEN_TTL is
  #      2 h by default), remove the old key from the map in a
  #      follow-up commit.
  data_json = jsonencode({
    keys = jsonencode({
      primary_kid = "v1"
      keys = {
        v1 = random_password.shop_jwt_signing_key.result
      }
    })
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
