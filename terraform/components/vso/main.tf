resource "helm_release" "vso" {
  name             = "vault-secrets-operator"
  namespace        = "vault-secrets-operator-system"
  create_namespace = true
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  version          = "0.9.0"

  set {
    name  = "defaultVaultConnection.enabled"
    value = "true"
  }
  set {
    name  = "defaultVaultConnection.address"
    value = var.vault_address
  }
  set {
    name  = "defaultVaultConnection.skipTLSVerify"
    value = "false"
  }
  set {
    name  = "defaultAuthMethod.enabled"
    value = "true"
  }
  set {
    name  = "defaultAuthMethod.method"
    value = "kubernetes"
  }
  set {
    name  = "defaultAuthMethod.mount"
    value = var.kubernetes_auth_path
  }
  set {
    name  = "defaultAuthMethod.kubernetes.role"
    value = "netlix-vso"
  }
  set {
    name  = "defaultAuthMethod.kubernetes.serviceAccount"
    value = "vault-secrets-operator"
  }
  set {
    name  = "defaultAuthMethod.namespace"
    value = var.vault_namespace
  }
}
