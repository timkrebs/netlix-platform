# Per-service Kubernetes auth backend roles (Phase 6.1, foundation).
#
# Each role is bound to a single ServiceAccount in the consul namespace
# (created in app/manifests/base/vso-impersonators.yaml). VSO impersonates
# the SA via TokenRequest, presents the resulting JWT to Vault, and
# authenticates as the role — which only carries the matching per-service
# policy.
#
# The legacy `netlix-vso` role in auth.tf stays as a backstop until
# every VaultStaticSecret is cut over to a per-service VaultAuth.

resource "vault_kubernetes_auth_backend_role" "shop_db" {
  namespace                        = vault_namespace.env.path_fq
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-shop-db"
  bound_service_account_names      = ["vso-shop-db"]
  bound_service_account_namespaces = ["consul"]
  token_policies                   = [vault_policy.shop_db_reader.name]
  token_ttl                        = 3600
  audience                         = "vault"
}

resource "vault_kubernetes_auth_backend_role" "shop_jwt" {
  namespace                        = vault_namespace.env.path_fq
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-shop-jwt"
  bound_service_account_names      = ["vso-shop-jwt"]
  bound_service_account_namespaces = ["consul"]
  token_policies                   = [vault_policy.shop_jwt_reader.name]
  token_ttl                        = 3600
  audience                         = "vault"
}

resource "vault_kubernetes_auth_backend_role" "shop_config" {
  namespace                        = vault_namespace.env.path_fq
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-shop-config"
  bound_service_account_names      = ["vso-shop-config"]
  bound_service_account_namespaces = ["consul"]
  token_policies                   = [vault_policy.shop_config_reader.name]
  token_ttl                        = 3600
  audience                         = "vault"
}

resource "vault_kubernetes_auth_backend_role" "shop_pki" {
  namespace                        = vault_namespace.env.path_fq
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-shop-pki"
  bound_service_account_names      = ["vso-shop-pki"]
  bound_service_account_namespaces = ["consul"]
  token_policies                   = [vault_policy.shop_pki_issuer.name]
  token_ttl                        = 3600
  audience                         = "vault"
}
