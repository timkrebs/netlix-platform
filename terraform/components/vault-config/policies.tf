resource "vault_policy" "vso" {
  name   = "netlix-vso-${var.environment}"
  policy = <<-EOT
    path "${vault_mount.pki_int.path}/issue/netlix-app" {
      capabilities = ["create", "update"]
    }
    path "${vault_mount.kv.path}/data/netlix/*" {
      capabilities = ["read"]
    }
    path "${vault_mount.database.path}/creds/netlix-readwrite" {
      capabilities = ["read"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_policy" "app" {
  name   = "netlix-app-${var.environment}"
  policy = <<-EOT
    path "${vault_mount.kv.path}/data/netlix/*" {
      capabilities = ["read"]
    }
    path "${vault_mount.database.path}/creds/netlix-readwrite" {
      capabilities = ["read"]
    }
    path "${vault_mount.pki_int.path}/issue/netlix-app" {
      capabilities = ["create", "update"]
    }
  EOT
}
