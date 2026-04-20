resource "vault_auth_backend" "kubernetes" {
  namespace = vault_namespace.env.path_fq
  type      = "kubernetes"
  path      = "kubernetes"
}

# ─── Kubernetes auth backend config ───────────────────────────────────────
# Vault runs in a separate cluster (vault-cluster) from the workloads
# (app-cluster), so it must call the app-cluster API for TokenReview.
# kubernetes_host / kubernetes_ca_cert / token_reviewer_jwt come from
# the calling app-cluster workspace via variables.

resource "vault_kubernetes_auth_backend_config" "eks" {
  namespace              = vault_namespace.env.path_fq
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = var.kubernetes_host
  kubernetes_ca_cert     = var.kubernetes_ca_cert
  token_reviewer_jwt     = var.token_reviewer_jwt
  disable_iss_validation = true
  disable_local_ca_jwt   = true
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
    # Auth backend management
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    path "sys/auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # Secrets engine management
    path "sys/mounts/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    path "sys/mounts" {
      capabilities = ["read", "list"]
    }

    # Policy management
    path "sys/policies/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Namespace management
    path "sys/namespaces/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # PKI and secrets engines
    path "pki/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    path "pki_int/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # KV secrets
    path "kv/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Database secrets engine
    path "database/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Token management
    path "auth/token/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # Health and status
    path "sys/health" {
      capabilities = ["read"]
    }
    path "sys/seal-status" {
      capabilities = ["read"]
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
    # TFC manages Vault configuration across child namespaces: auth backends,
    # secrets engines, PKI, policies, and database connections.

    # Namespace management (create/manage child namespaces)
    path "sys/namespaces/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Auth backend management
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    path "sys/auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # Secrets engine mounts
    path "sys/mounts/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    path "sys/mounts" {
      capabilities = ["read", "list"]
    }

    # Policy management
    path "sys/policies/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # PKI engines (root + intermediate signing)
    path "pki/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    path "pki_int/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # KV secrets
    path "kv/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Database secrets engine
    path "database/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Token self-management
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
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
