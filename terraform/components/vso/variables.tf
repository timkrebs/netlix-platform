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
  description = "Name of the Kubernetes secret containing the Vault CA certificate (in vault namespace)"
  type        = string
  default     = "vault-ca"
}
