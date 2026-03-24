# Root CA
resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "Netlix root PKI"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "Netlix Internal CA"
  ttl         = "87600h"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_config_urls" "urls" {
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["${local.vault_addr}/v1/${vault_mount.pki.path}/ca"]
  crl_distribution_points = ["${local.vault_addr}/v1/${vault_mount.pki.path}/crl"]
}

# Intermediate CA
resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Netlix intermediate PKI"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 43200
}

resource "vault_pki_secret_backend_intermediate_cert_request" "int" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Netlix Intermediate CA"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_root_sign_intermediate" "int" {
  backend     = vault_mount.pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.int.csr
  common_name = "Netlix Intermediate CA"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "int" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.int.certificate
}

resource "vault_pki_secret_backend_role" "app" {
  backend          = vault_mount.pki_int.path
  name             = "netlix-app"
  allowed_domains  = var.pki_allowed_domains
  allow_subdomains = true
  max_ttl          = "72h"
  key_type         = "ec"
  key_bits         = 256
  require_cn       = false

  key_usage = ["DigitalSignature", "KeyAgreement", "KeyEncipherment"]

  lifecycle {
    ignore_changes = [key_usage]
  }
}
