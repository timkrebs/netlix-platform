# Grants the userpass admin entities (created in vault-cluster) full
# access to this environment's Vault namespace.
#
# In Vault Enterprise, namespaces are isolated — a token from the root
# namespace can't act in `dev` unless the entity is granted a policy in
# `dev` via a group whose member_entity_ids references the root entity.
#
# Two entities can be members:
#   - admin_entity_id    — included in every environment
#   - dev_user_entity_id — included only when environment == "dev",
#                          producing a user that has admin in dev and
#                          nothing elsewhere
#
# Skipped entirely if admin_entity_id is empty (e.g. the very first plan
# before vault-cluster has been re-applied with the entity resource).

locals {
  namespace_admin_members = compact([
    var.admin_entity_id,
    var.environment == "dev" ? var.dev_user_entity_id : "",
  ])
}

resource "vault_policy" "namespace_admin" {
  count = var.admin_entity_id == "" ? 0 : 1

  namespace = vault_namespace.env.path_fq
  name      = "namespace-admin"

  policy = <<-EOT
    # Full access to every path in this namespace.
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

resource "vault_identity_group" "namespace_admins" {
  count = var.admin_entity_id == "" ? 0 : 1

  namespace         = vault_namespace.env.path_fq
  name              = "namespace-admins"
  type              = "internal"
  policies          = [vault_policy.namespace_admin[0].name]
  member_entity_ids = local.namespace_admin_members
}
