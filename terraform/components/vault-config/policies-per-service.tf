# Per-service Vault policies (Phase 6.1, foundation).
#
# These exist alongside the legacy `netlix-vso` (catch-all) policy in
# policies.tf. Each policy is scoped to a single KVv2 path or PKI role,
# so a compromise of one consumer SA only exposes that one secret class.
#
# The legacy `netlix-vso` policy stays in place as a backstop until every
# VaultStaticSecret is cut over to the corresponding per-service VaultAuth.
# After cutover (Phase 6.1 Commit B), the legacy policy can be deprecated
# and eventually removed.

# Reads only the database credentials Secret.
resource "vault_policy" "shop_db_reader" {
  namespace = vault_namespace.env.path_fq
  name      = "netlix-shop-db-reader"
  policy    = <<-EOT
    path "secret/data/netlix/db" {
      capabilities = ["read"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}

# Reads only the JWT signing-key Secret.
resource "vault_policy" "shop_jwt_reader" {
  namespace = vault_namespace.env.path_fq
  name      = "netlix-shop-jwt-reader"
  policy    = <<-EOT
    path "secret/data/netlix/jwt" {
      capabilities = ["read"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}

# Reads only the feature-flag Secret. Used by the gateway (which serves
# /api/flags from the projected file).
resource "vault_policy" "shop_config_reader" {
  namespace = vault_namespace.env.path_fq
  name      = "netlix-shop-config-reader"
  policy    = <<-EOT
    path "secret/data/netlix/featureflags" {
      capabilities = ["read"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}

# Issues short-lived service certs from the intermediate PKI role only.
# Notably has NO read on secret/data/netlix/* — a stolen PKI-issuer SA
# can mint a cert but cannot read any secret.
resource "vault_policy" "shop_pki_issuer" {
  namespace = vault_namespace.env.path_fq
  name      = "netlix-shop-pki-issuer"
  policy    = <<-EOT
    path "pki_int/issue/netlix-app" {
      capabilities = ["create", "update"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}
