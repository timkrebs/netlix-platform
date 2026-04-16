# ─── cert-manager TLS for Vault server ─────────────────────────────────────
#
# Chain: SelfSigned Issuer → CA Certificate → CA Issuer → Server Certificate
#
# Uses kubectl_manifest instead of kubernetes_manifest because the latter
# requires an API connection at plan time (to validate CRD schemas), which
# fails on initial deploy when the EKS cluster doesn't yet exist.

resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubectl_manifest" "selfsigned_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "vault-selfsigned"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      selfSigned = {}
    }
  })
}

resource "kubectl_manifest" "vault_ca_cert" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "vault-ca"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      isCA       = true
      commonName = "Vault CA"
      secretName = "vault-ca"
      duration   = "87600h"
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      issuerRef = {
        name  = "vault-selfsigned"
        kind  = "Issuer"
        group = "cert-manager.io"
      }
    }
  })

  depends_on = [kubectl_manifest.selfsigned_issuer]
}

resource "kubectl_manifest" "vault_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "vault-ca-issuer"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      ca = {
        secretName = "vault-ca"
      }
    }
  })

  depends_on = [kubectl_manifest.vault_ca_cert]
}

resource "kubectl_manifest" "vault_server_cert" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "vault-server-tls"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      secretName  = "vault-server-tls"
      duration    = "8760h"
      renewBefore = "720h"
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      commonName = "vault.vault.svc.cluster.local"
      dnsNames = [
        "vault.vault.svc.cluster.local",
        "vault.vault.svc",
        "vault.vault",
        "vault",
        "vault-active.vault.svc.cluster.local",
        "vault-standby.vault.svc.cluster.local",
        "vault-internal.vault.svc.cluster.local",
        "*.vault-internal",
        "*.vault-internal.vault.svc.cluster.local",
        "vault.${var.environment}.${var.domain}",
        "localhost",
      ]
      ipAddresses = ["127.0.0.1"]
      issuerRef = {
        name  = "vault-ca-issuer"
        kind  = "Issuer"
        group = "cert-manager.io"
      }
    }
  })

  depends_on = [kubectl_manifest.vault_ca_issuer]
}
