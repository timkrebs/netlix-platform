# Phase 6.3 — Long-lived non-root admin token for ongoing TF operations.
#
# The vault-cluster workspace's provider currently authenticates with
# `var.vault_root_token` (see providers.tf), which lives in HCP TF state
# forever and was never rotated after initial bootstrap. That is a
# known PSIRT finding from the Phase 5 audit.
#
# This resource issues a long-lived (1 year), renewable, NON-ROOT admin
# token from the same admin policy used by the userpass admin user
# (see auth.tf:15). It carries identical capabilities on the root
# namespace's auth/secrets/policy/PKI/KV paths, but expires, can be
# revoked individually, and its issuance is audit-logged.
#
# This commit does NOT yet swap the provider over to the new token —
# that is an operator-driven, one-time bootstrap step documented in
# docs/vault-root-rotation.md. After completing the runbook, the
# original root token is revoked and the workspace's `vault_root_token`
# variable holds this token instead.

resource "vault_token" "tf_admin" {
  policies          = [vault_policy.admin.name]
  no_default_policy = false

  # 1-year TTL with explicit_max_ttl matching. Renewable so the
  # operator can extend before expiry; rotation cadence target is
  # annual to keep a fresh audit-log trail of the issuance event.
  ttl              = "8760h"
  explicit_max_ttl = "8760h"
  renewable        = true

  metadata = {
    purpose   = "tf-ongoing-ops"
    issued_by = "vault-cluster-workspace"
    rotation  = "annual"
  }
}

# Sensitive output — the operator copies this into HCP TF's
# `vault_root_token` workspace variable per the rotation runbook.
#
# The Vault provider's `vault_token` resource exports the secret value
# but not the accessor. To clean up the token during rotation, look the
# accessor up at runtime:
#
#   VAULT_TOKEN=$(terraform output -raw tf_admin_token) \
#     vault token lookup -format=json | jq -r .data.accessor
#
# (See docs/vault-root-rotation.md.)
output "tf_admin_token" {
  description = "Non-root admin token for ongoing TF operations. After bootstrap, copy this value into the HCP TF workspace variable `vault_root_token` (replacing the original root) per docs/vault-root-rotation.md, then revoke the original root via `vault operator generate-root` + `vault token revoke -accessor`."
  value       = vault_token.tf_admin.client_token
  sensitive   = true
}
