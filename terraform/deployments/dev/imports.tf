# Temporary import blocks for adopting existing Vault resources into state.
# Remove after the first successful apply.
# AWS resources were cleaned up and will be created fresh.

import {
  to = module.vault_config.vault_auth_backend.kubernetes
  id = "kubernetes/netlix-${var.environment}"
}

import {
  to = module.vault_config.vault_auth_backend.userpass
  id = "userpass"
}

import {
  to = module.vault_config.vault_mount.database
  id = "database"
}

import {
  to = module.vault_config.vault_mount.kv
  id = "secret"
}

import {
  to = module.vault_config.vault_mount.pki
  id = "pki"
}

import {
  to = module.vault_config.vault_mount.pki_int
  id = "pki_int"
}
