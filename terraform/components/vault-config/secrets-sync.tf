# Vault Secrets Sync requires the vault provider >= 4.2.0 with Enterprise/HCP Vault.
# Uncomment and configure when secrets sync is available in your Vault cluster.
#
# resource "vault_secrets_sync_gh_destination" "ci" {
#   name          = "netlix-ci-secrets"
#   access_token  = var.github_pat
#   repository_owner = var.github_org
#   repository_name  = "netlix-platform"
# }
