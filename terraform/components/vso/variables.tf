variable "vault_address" {
  description = "Vault cluster address (internal for in-cluster access)"
  type        = string
}

variable "vault_namespace" {
  description = "Vault namespace"
  type        = string
}

variable "kubernetes_auth_path" {
  description = "Vault Kubernetes auth mount path"
  type        = string
}

variable "vault_ca_secret_name" {
  description = "Name of the Kubernetes secret containing the Vault CA certificate. Empty string uses the system trust store."
  type        = string
  default     = ""
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS verification for Vault connection (use when Vault runs on a separate cluster and the CA cert is not available locally)"
  type        = bool
  default     = false
}
