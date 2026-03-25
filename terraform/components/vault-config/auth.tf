resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes/netlix-${var.environment}"
}

resource "vault_kubernetes_auth_backend_config" "eks" {
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = var.eks_cluster_endpoint
  kubernetes_ca_cert     = base64decode(var.eks_cluster_ca)
  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "vso" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-vso"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator-system"]
  token_policies                   = [vault_policy.vso.name]
  token_ttl                        = 3600
}

# ─── Userpass auth for admin access ────────────────────────────────────────
# The auth backend and policy are managed by Terraform.
# Create the admin user after deploy via Vault CLI or UI:
#   vault write auth/userpass/users/timkrebs password=<pw> policies=admin-policy

resource "vault_auth_backend" "userpass" {
  count = var.create_shared_resources ? 1 : 0
  type  = "userpass"
  path  = "userpass"
}

resource "vault_policy" "admin" {
  count  = var.create_shared_resources ? 1 : 0
  name   = "admin-policy"
  policy = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

# ─── Kubernetes auth roles ─────────────────────────────────────────────────

resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-app"
  bound_service_account_names      = ["netlix-app"]
  bound_service_account_namespaces = ["netlix"]
  token_policies                   = [vault_policy.app.name]
  token_ttl                        = 3600
}
