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
