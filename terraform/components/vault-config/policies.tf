resource "vault_policy" "vso" {
  name   = "netlix-vso"
  policy = <<-EOT
    path "pki_int/issue/netlix-app" {
      capabilities = ["create", "update"]
    }
    path "secret/data/netlix/*" {
      capabilities = ["read"]
    }
    path "database/creds/netlix-readwrite" {
      capabilities = ["read"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_policy" "app" {
  name   = "netlix-app"
  policy = <<-EOT
    path "secret/data/netlix/*" {
      capabilities = ["read"]
    }
    path "database/creds/netlix-readwrite" {
      capabilities = ["read"]
    }
    path "pki_int/issue/netlix-app" {
      capabilities = ["create", "update"]
    }
  EOT
}
