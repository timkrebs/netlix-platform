# Vault audit device → container stdout. The kubelet captures stdout into
# /var/log/containers, where Promtail tails it and forwards to Loki. The
# helm chart's auditStorage PVC is preserved separately for compliance.

resource "vault_audit" "stdout" {
  namespace = vault_namespace.env.path_fq
  type      = "file"
  path      = "stdout"

  options = {
    file_path = "stdout"
  }
}
