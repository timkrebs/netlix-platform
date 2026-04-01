output "vault_public_endpoint" { value = local.vault_addr }
output "vault_namespace" { value = vault_namespace.env.path_fq }
output "kubernetes_auth_path" { value = vault_auth_backend.kubernetes.path }
output "pki_backend_path" { value = vault_mount.pki_int.path }
