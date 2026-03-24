resource "vault_secrets_sync_github_apps_destination" "ci" {
  name                 = "netlix-ci-secrets"
  access_token         = var.github_pat
  repository_owner     = var.github_org
  repository_name      = "netlix-platform"
  secret_name_template = "VAULT_{{ .SecretKey | uppercase }}"
}

resource "vault_secrets_sync_association" "docker_registry" {
  name        = vault_secrets_sync_github_apps_destination.ci.name
  type        = "gh"
  mount       = vault_mount.kv.path
  secret_name = "netlix/ci-registry"
}
