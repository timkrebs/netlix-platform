resource "vault_auth_backend" "kubernetes" {
  namespace = vault_namespace.env.path_fq
  type      = "kubernetes"
  path      = "kubernetes"
}

# ─── Token reviewer SA for HCP Vault K8s auth ────────────────────────────
# HCP Vault is external to the cluster and needs a long-lived SA token
# to call the TokenReview API and validate K8s service account tokens.

resource "kubernetes_service_account" "vault_token_reviewer" {
  metadata {
    name      = "vault-token-reviewer"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "vault_token_reviewer" {
  metadata {
    name = "vault-token-reviewer-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_token_reviewer.metadata[0].name
    namespace = "kube-system"
  }
}

resource "kubernetes_secret" "vault_token_reviewer" {
  metadata {
    name      = "vault-token-reviewer-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.vault_token_reviewer.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

resource "vault_kubernetes_auth_backend_config" "eks" {
  namespace              = vault_namespace.env.path_fq
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = var.eks_cluster_endpoint
  kubernetes_ca_cert     = base64decode(var.eks_cluster_ca)
  token_reviewer_jwt     = kubernetes_secret.vault_token_reviewer.data["token"]
  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "vso" {
  namespace                        = vault_namespace.env.path_fq
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-vso"
  bound_service_account_names      = ["vault-secrets-operator", "vault-secrets-operator-controller-manager"]
  bound_service_account_namespaces = ["vault-secrets-operator-system", "consul"]
  token_policies                   = [vault_policy.vso.name]
  token_ttl                        = 3600
}

# ─── Userpass auth for admin access (shared in admin namespace) ──────────
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

# ─── JWT auth for HCP Terraform dynamic credentials (shared) ────────────
# Allows TFC Stacks runs to authenticate to Vault via OIDC instead of a
# static token. Scoped to the TFC organization.

resource "vault_jwt_auth_backend" "tfc" {
  count              = var.create_shared_resources ? 1 : 0
  path               = "jwt-tfc"
  type               = "jwt"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
}

resource "vault_policy" "tfc" {
  count = var.create_shared_resources ? 1 : 0
  name  = "tfc-policy"

  policy = <<-EOT
    # TFC manages Vault configuration across child namespaces (admin/dev,
    # admin/staging) including auth backends, secrets engines, PKI, policies,
    # and database connections. HCP Vault requires full access at the parent
    # namespace for cross-namespace operations — scoped paths do not propagate.
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

resource "vault_jwt_auth_backend_role" "tfc" {
  count     = var.create_shared_resources ? 1 : 0
  backend   = vault_jwt_auth_backend.tfc[0].path
  role_name = "tfc-stacks"
  role_type = "jwt"

  bound_audiences   = ["vault.workload.identity"]
  bound_claims_type = "glob"
  bound_claims = {
    sub = "organization:${var.tfc_organization_name}:project:*:stack:*:deployment:*:operation:*"
  }

  user_claim     = "sub"
  token_policies = [vault_policy.tfc[0].name]
  token_ttl      = 1200
  token_max_ttl  = 3600
}

# ─── Kubernetes auth roles ─────────────────────────────────────────────────

resource "vault_kubernetes_auth_backend_role" "app" {
  namespace                        = vault_namespace.env.path_fq
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netlix-app"
  bound_service_account_names      = ["netlix-app"]
  bound_service_account_namespaces = ["netlix"]
  token_policies                   = [vault_policy.app.name]
  token_ttl                        = 3600
}
