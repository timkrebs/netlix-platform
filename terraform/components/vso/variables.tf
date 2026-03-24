variable "vault_address" {
  description = "Vault cluster address"
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
