# Vault audit device → container stdout. The kubelet captures stdout into
# /var/log/containers, where Promtail tails it and forwards to Loki. The
# helm chart's auditStorage PVC is preserved separately for compliance.
#
# Audit devices in Vault Enterprise are a root-namespace primitive — they
# cannot be enabled inside a child namespace. Omitting `namespace` here
# targets the root namespace (the provider is authenticated with a root
# token and has no default namespace set in providers.tf). Root-level
# audit captures requests across all namespaces, including `dev`.

resource "vault_audit" "stdout" {
  type = "file"
  path = "stdout"

  options = {
    file_path = "stdout"
  }
}
