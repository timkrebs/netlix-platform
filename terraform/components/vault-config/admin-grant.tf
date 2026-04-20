# Grants the userpass admin user (entity created in vault-cluster) full
# access to this environment's Vault namespace.
#
# In Vault Enterprise, namespaces are isolated — a token from the root
# namespace can't act in `dev` unless the entity is granted a policy in
# `dev` via a group whose member_entity_ids references the root entity.
#
# Skipped when admin_entity_id is empty (e.g. during the very first plan
# before vault-cluster has been applied).

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
  member_entity_ids = [var.admin_entity_id]
}
