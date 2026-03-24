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

resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-app"
  bound_service_account_names      = ["netlix-app"]
  bound_service_account_namespaces = ["netlix"]
  token_policies                   = [vault_policy.app.name]
  token_ttl                        = 3600
}
