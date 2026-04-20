# ─── Userpass auth method (root namespace) ───────────────────────────────
# Bootstrapped here so the Vault cluster ships with a usable admin login
# right after init. Username/password come from HCP TF workspace variables.

import {
  to = vault_auth_backend.userpass
  id = "userpass"
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

resource "vault_policy" "admin" {
  name = "admin-policy"

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

resource "vault_generic_endpoint" "admin_user" {
  path                 = "auth/${vault_auth_backend.userpass.path}/users/${var.username}"
  ignore_absent_fields = true

  data_json = jsonencode({
    password = var.password
    policies = [vault_policy.admin.name]
  })
}

# ─── Identity entity + userpass alias ────────────────────────────────────
# Creates a single global identity for the admin user. Per-env namespaces
# (created by vault-config) attach their own admin policy to this entity
# via vault_identity_group, giving the user admin in every namespace.

resource "vault_identity_entity" "admin" {
  name     = var.username
  policies = [vault_policy.admin.name]
}

import {
  to = vault_identity_entity_alias.admin_userpass
  id = "f9cd1506-a22e-3ca0-d166-a7bde7df6eb9"
}

resource "vault_identity_entity_alias" "admin_userpass" {
  name           = var.username
  mount_accessor = vault_auth_backend.userpass.accessor
  canonical_id   = vault_identity_entity.admin.id
}
