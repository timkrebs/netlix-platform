# Per-environment userpass auth backend mounted INSIDE this env's Vault
# namespace. A user authenticated here gets a token already scoped to
# the env namespace with the namespace-admin policy attached directly —
# no cross-namespace identity gymnastics, and the Vault UI can land
# directly in the env after login (Namespace: dev on the login form).
#
# Only created when both dev_user and dev_password are non-empty so the
# resource can be safely added to staging without forcing a credential.

locals {
  env_userpass_enabled = var.dev_user != "" && var.dev_password != ""
}

resource "vault_auth_backend" "env_userpass" {
  count = local.env_userpass_enabled ? 1 : 0

  namespace   = vault_namespace.env.path_fq
  type        = "userpass"
  path        = "userpass"
  description = "Per-environment userpass auth — login lands directly in ${var.environment} namespace"
}

resource "vault_generic_endpoint" "env_user" {
  count = local.env_userpass_enabled ? 1 : 0

  namespace            = vault_namespace.env.path_fq
  path                 = "auth/${vault_auth_backend.env_userpass[0].path}/users/${var.dev_user}"
  ignore_absent_fields = true

  data_json = jsonencode({
    password = var.dev_password
    policies = var.admin_entity_id == "" ? ["default"] : [vault_policy.namespace_admin[0].name]
  })
}
