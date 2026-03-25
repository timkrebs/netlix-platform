# Import existing resources into Stacks state.
# These blocks can be removed after the first successful apply.

import {
  to = vault_auth_backend.kubernetes
  id = "kubernetes/netlix-${var.environment}"
}

import {
  to = vault_auth_backend.userpass
  id = "userpass"
}

import {
  to = vault_mount.database
  id = "database"
}

import {
  to = vault_mount.kv
  id = "secret"
}

import {
  to = vault_mount.pki
  id = "pki"
}

import {
  to = vault_mount.pki_int
  id = "pki_int"
}
