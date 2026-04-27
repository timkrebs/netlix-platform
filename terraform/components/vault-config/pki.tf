# Root CA (shared in admin namespace — created only by the primary environment)
resource "vault_mount" "pki" {
  count                     = var.create_shared_resources ? 1 : 0
  path                      = "pki"
  type                      = "pki"
  description               = "Netlix root PKI"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_pki_secret_backend_root_cert" "root" {
  count       = var.create_shared_resources ? 1 : 0
  backend     = vault_mount.pki[0].path
  type        = "internal"
  common_name = "Netlix Internal CA"
  ttl         = "87600h"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_config_urls" "urls" {
  count                   = var.create_shared_resources ? 1 : 0
  backend                 = vault_mount.pki[0].path
  issuing_certificates    = ["${local.vault_addr}/v1/${vault_mount.pki[0].path}/ca"]
  crl_distribution_points = ["${local.vault_addr}/v1/${vault_mount.pki[0].path}/crl"]
}

# Intermediate CA (per-environment namespace)
resource "vault_mount" "pki_int" {
  namespace                 = vault_namespace.env.path_fq
  path                      = "pki_int"
  type                      = "pki"
  description               = "Netlix ${var.environment} intermediate PKI"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 43200
}

resource "vault_pki_secret_backend_intermediate_cert_request" "int" {
  namespace   = vault_namespace.env.path_fq
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Netlix ${var.environment} Intermediate CA"
  key_type    = "ec"
  key_bits    = 256
}

# Cross-namespace: root CA in admin signs the intermediate
resource "vault_pki_secret_backend_root_sign_intermediate" "int" {
  backend     = "pki"
  csr         = vault_pki_secret_backend_intermediate_cert_request.int.csr
  common_name = "Netlix ${var.environment} Intermediate CA"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "int" {
  namespace   = vault_namespace.env.path_fq
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.int.certificate
}

resource "vault_generic_endpoint" "pki_role_app" {
  namespace            = vault_namespace.env.path_fq
  path                 = "${vault_mount.pki_int.path}/roles/netlix-app"
  ignore_absent_fields = true
  disable_read         = true

  data_json = jsonencode({
    allowed_domains  = var.pki_allowed_domains
    allow_subdomains = true
    default_ttl      = "3600"
    max_ttl          = "3600"
    key_type         = "ec"
    key_bits         = 256
    require_cn       = false
    server_flag      = true
    client_flag      = true
    key_usage        = ["DigitalSignature", "KeyAgreement", "KeyEncipherment"]
    ext_key_usage    = ["ServerAuth", "ClientAuth"]
  })
}
